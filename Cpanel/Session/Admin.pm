package Cpanel::Session::Admin;

# cpanel - Cpanel/Session/Admin.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Rand::Get                    ();
use Cpanel::FileUtils::Open              ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::LineTerminatorFree ();

our $ADMIN_SESSION_STORAGE_DIR = '/var/cpanel/adminsessions';
our $ADMIN_SESSION_FILE_PERMS  = 0600;
our $SESSION_AND_KEY_LENGTH    = 16;
our $RAND_DATA_PRELOAD_COUNT   = 10;

sub create_impersonation_session {
    my ($real_user) = @_;

    Cpanel::Validate::LineTerminatorFree::validate_or_die($real_user);

    my $randsession;
    while ( !$randsession || -e _get_impersonation_session_path($randsession) ) {
        $randsession = Cpanel::Rand::Get::getranddata( $SESSION_AND_KEY_LENGTH, undef, $RAND_DATA_PRELOAD_COUNT );
    }
    my $sessionkey = Cpanel::Rand::Get::getranddata( $SESSION_AND_KEY_LENGTH, undef, $RAND_DATA_PRELOAD_COUNT );

    Cpanel::FileUtils::Open::sysopen_with_real_perms( my $session_file, _get_impersonation_session_path($randsession), 'O_WRONLY|O_CREAT|O_EXCL', $ADMIN_SESSION_FILE_PERMS )
      or die "Failed to write adminsession file: $randsession: because of an error: $!";
    print {$session_file} "key=$sessionkey\nuser=$real_user\n";
    close $session_file;

    $ENV{'CPRESELLERSESSION'}    = $randsession;
    $ENV{'CPRESELLERSESSIONKEY'} = $sessionkey;

    return;
}

sub get_user_in_impersonation_session_if_key_matches {
    my ( $session, $key ) = @_;

    my $ref = _load_impersonation_session($session);
    if ( $ref && $ref->{'key'} && $ref->{'key'} eq $key ) {
        return $ref->{'user'};
    }
    return undef;
}

sub _get_impersonation_session_path {
    my ($session) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($session);
    return "$ADMIN_SESSION_STORAGE_DIR/$session";
}

sub _load_impersonation_session {
    my ($session) = @_;
    my $sessionfile = _get_impersonation_session_path($session);
    return scalar Cpanel::Config::LoadConfig::loadConfig( $sessionfile, undef, '=' );
}

1;
