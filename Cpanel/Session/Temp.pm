package Cpanel::Session::Temp;

# cpanel - Cpanel/Session/Temp.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AdminBin::Serializer    ();
use Cpanel::Config::Session         ();
use Cpanel::LoadModule              ();
use Cpanel::FastSpawn::InOut        ();
use Cpanel::Session::Constants      ();
use Cpanel::Rand::Get               ();
use Cpanel::FileUtils::Write        ();
use Cpanel::PwCache                 ();
use Cpanel::AcctUtils::Account      ();
use Cpanel::Debug                   ();
use Cpanel::Exception               ();
use Cpanel::DB::Utils               ();
use Cpanel::Session::Temp::Validate ();
use Try::Tiny;

our $VERSION = 1.2;

sub link_session_temp_user_to_session {
    my ( $session_temp_user, $session ) = @_;

    return symlink( "$Cpanel::Config::Session::SESSION_DIR/raw/$session", "$Cpanel::Session::Constants::CPSES_LOOKUP_DIR/$session_temp_user" );
}

sub get_session_from_temp_username {
    my ($session_temp_user) = @_;
    if ( $session_temp_user =~ tr{/}{} ) { die "The session_temp_user “$session_temp_user” may not contain a “/”."; }
    my $target = readlink("$Cpanel::Session::Constants::CPSES_LOOKUP_DIR/$session_temp_user");
    return if !$target;
    return ( split( m{/+}, $target ) )[-1];
}

sub full_username_from_temp_user {
    my ( $user, $temp_user ) = @_;

    if ( $temp_user =~ m/^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E/ ) {

        # We already have the full username.

        Cpanel::Debug::log_warn("full temp username: $temp_user passed to full_username_from_temp_user");

        return $temp_user;
    }

    # If the length of prefix is ever changed from 2 characters, update the pam module as it
    # expects an exact length of 10 characters for the prefix + username
    # /u/l/c/src/pam_cpses/pam_cpses.c
    my $prefix = $Cpanel::Session::Constants::TEMP_USER_PREFIX . substr( $user, 0, 2 );

    return $prefix . $temp_user;
}

sub generate_temp_user_and_pass {
    my ($user) = @_;

    my $prefix = $Cpanel::Session::Constants::TEMP_USER_PREFIX . substr( $user, 0, 2 );

    my $safety = 0;

    # If the length of the session_temp_user ever changed from 8 characters, update the pam module
    # as it expects an exact length of 10 characters for the prefix + username
    # /u/l/c/src/pam_cpses/pam_cpses.c
    #
    # The username must be lowercase since imap users are not case sensitive
    my $session_temp_user = Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9, 'a' .. 'z' ] );
    while ( Cpanel::AcctUtils::Account::accountexists( $prefix . $session_temp_user ) && $safety++ < 256 ) {
        $session_temp_user = Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9, 'a' .. 'z' ] );
    }
    return ( $session_temp_user, Cpanel::Rand::Get::getranddata(32) );
}

sub create_temp_user {
    my ( $user, $session_temp_user, $session_temp_pass ) = @_;

    return _temp_user( 'CREATE', $user, $session_temp_user, $session_temp_pass );
}

#NOTE: The first parameter is the already-authenticated user.
#The second and third are the result of giving that user to generate_temp_user_and_pass().
#
#TODO: Simplify this interface: just call generate_temp_user_and_pass()
#within here.
#
sub create_session_key {
    my ( $user, $session_temp_user, $session_temp_pass ) = @_;

    my $cpses_temp_user        = full_username_from_temp_user( $user, $session_temp_user );
    my $safe_session_temp_user = $user . ':' . $cpses_temp_user;
    if ( Cpanel::Session::Temp::Validate::is_valid_session_user_token($cpses_temp_user) && Cpanel::Session::Temp::Validate::is_valid_session_user_token($user) ) {
        if ( Cpanel::FileUtils::Write::overwrite_no_exceptions( "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user", $session_temp_pass, 0640 ) ) {
            my $safe_session_temp_user_clean = Cpanel::DB::Utils::username_to_dbowner($user) . ':' . $cpses_temp_user;

            # If the username has underscores in it, then we need to create a symlink for the 'clean' variant
            # of the session file, so that these users' utilities (phppgadmin, etc) are still accessible to the reseller/root.
            if ( $safe_session_temp_user ne $safe_session_temp_user_clean && !-e "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user_clean" ) {
                symlink "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user", "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user_clean";
            }
            my $cpses_gid = ( Cpanel::PwCache::getpwnam('cpses') )[3];
            chown 0, $cpses_gid, "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user";
        }
        else {
            Cpanel::Debug::log_warn("Could not write cpses key file: “$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user”");
            return 0;
        }
    }
    else {
        Cpanel::Debug::log_warn("Attempt to create session: “$safe_session_temp_user” was not a valid session name");
        return 0;
    }
    return 1;
}

sub remove_temp_user {
    my ( $user, $session_temp_user, $created_session_temp_user ) = @_;

    my $safe_session_temp_user       = $user . ':' . full_username_from_temp_user( $user, $session_temp_user );
    my $safe_session_temp_user_clean = Cpanel::DB::Utils::username_to_dbowner($user) . ':' . full_username_from_temp_user( $user, $session_temp_user );

    die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid username because it contains a “[_2]” character.', [ $safe_session_temp_user, '/' ] ) if $safe_session_temp_user =~ tr{/}{};

    # If there is a symlink for the 'clean' (ie. stripped off underscores) variant of the temp user,
    # and that symlink points the session file we are removing, then unlink it also.
    if ( -l "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user_clean" && readlink("$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user_clean") eq "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user" ) {
        unlink("$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user_clean");
    }

    unlink( "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$safe_session_temp_user", "$Cpanel::Session::Constants::CPSES_LOOKUP_DIR/$session_temp_user" );

    # Only remove the key if we didn't
    # actually create the temp session user.
    return 1 if !$created_session_temp_user;

    return _temp_user( 'REMOVE', $user, $session_temp_user );
}

sub _temp_user {
    my ( $action, $user, $session_temp_user, $session_temp_pass ) = @_;

    my $request = Cpanel::AdminBin::Serializer::Dump(
        {
            'action'        => $action . 'TEMPDBOWNER',
            'user'          => $user,
            'background'    => ( $action eq 'REMOVE' ? 1 : 0 ),
            'one_time_user' => $session_temp_user,
            'one_time_pass' => ( $session_temp_pass || '' ),
        }
    );

    #TODO: Replace with Cpanel::SafeRun::Object.
    if ( my $pid = Cpanel::FastSpawn::InOut::inout( my $cpses_wtr, my $cpses_rdr, '/usr/local/cpanel/bin/cpses_tool' ) ) {
        local $?;

        print {$cpses_wtr} $request;
        close($cpses_wtr);
        local $/;
        my $response = readline($cpses_rdr);
        if ($response) {
            Cpanel::Debug::log_warn("Unexpected response from cpses_tool: $response");
            return 0;
        }
        close($cpses_rdr);

        _waitpid( $pid, 0 );

        if ($?) {
            Cpanel::LoadModule::load_perl_module('Cpanel::ChildErrorStringifier');
            Cpanel::Debug::log_warn( "Unexpected error from cpses_tool: " . Cpanel::ChildErrorStringifier->new($?)->autopsy() );
            return 0;
        }

        return 1;
    }

    return 0;
}

#
#  Check to ensure that a session_temp_user is assoicated with a
#  system user
#
sub session_temp_user_owner_check {
    my ( $user, $session_temp_user ) = @_;

    my $cpses_user = $session_temp_user =~ m/^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E/ ? $session_temp_user : full_username_from_temp_user( $user, $session_temp_user );

    return ( -e "$Cpanel::Session::Constants::CPSES_KEYS_DIR/$user:$cpses_user" ? 1 : 0 );
}

# for tests
sub _waitpid {
    my ( $pid, $flags ) = @_;
    return waitpid( $pid, $flags );
}

1;
