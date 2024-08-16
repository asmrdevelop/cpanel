package Cpanel::Session::Temp::Check;

# cpanel - Cpanel/Session/Temp/Check.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadFile                ();
use Cpanel::LoadModule              ();
use Cpanel::Session::Constants      ();
use Cpanel::Session::Temp::Validate ();
use Cpanel::Debug                   ();

use Try::Tiny;

sub get_temp_session_password {
    my ( $user, $temp_session_user ) = @_;

    if ( !Cpanel::Session::Temp::Validate::is_valid_session_user_token($user) ) {
        Cpanel::Debug::log_warn("Attempt to check the password for an invalid user: “$user” was not a valid username.");
        return;
    }

    if ( !Cpanel::Session::Temp::Validate::is_valid_session_user_token($temp_session_user) ) {
        Cpanel::Debug::log_warn("Attempt to check the password for an invalid temp session user: “$temp_session_user” was not a valid username.");
        return;
    }

    my ( $pass_on_disk, $err );
    try {
        $pass_on_disk = Cpanel::LoadFile::load("$Cpanel::Session::Constants::CPSES_KEYS_DIR/$user:$temp_session_user");
    }
    catch {
        $err = $_;
    };

    if ($err) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Exception');
        Cpanel::Debug::log_warn( "Attempt to check the password temp session user “$temp_session_user” resulted in an error while reading the session file: " . Cpanel::Exception::get_string($err) );
        return;
    }

    return $pass_on_disk;
}

sub check_temp_session_password {
    my ( $user, $temp_session_user, $temp_session_password ) = @_;
    my $pass_on_disk = get_temp_session_password( $user, $temp_session_user );
    return $pass_on_disk if !$pass_on_disk;
    return ( $pass_on_disk eq $temp_session_password ) ? 1 : 0;
}

1;
