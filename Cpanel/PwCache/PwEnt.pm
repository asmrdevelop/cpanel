package Cpanel::PwCache::PwEnt;

# cpanel - Cpanel/PwCache/PwEnt.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::PwCache::Helpers ();

my ( $isopen, $getpwent_open_time, $getpwent_passwd_fh, @SHAREDPW ) = (0);

sub getpwent {
    my ( $passwdmtime, $shadowmtime, $cryptpw ) = @_;

    if ( $INC{'B/C.pm'} ) {
        Cpanel::PwCache::Helpers::confess("Cpanel::PwCache::PwEnt::getpwent cannot be run under B::C (see case 162857)");
    }

    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    if ( !$isopen ) {
        if ($getpwent_passwd_fh) { close($getpwent_passwd_fh); }
        open( $getpwent_passwd_fh, '<', "$SYSTEM_CONF_DIR/passwd" ) or do {
            Cpanel::PwCache::Helpers::cluck("Unable to open $SYSTEM_CONF_DIR/passwd: $!");
            return;
        };
        $getpwent_open_time = ( stat("$SYSTEM_CONF_DIR/passwd") )[9];
        $shadowmtime        = $passwdmtime = $getpwent_open_time;

        #we did not read the shadow file so set it the same
        $isopen = 1;
    }
    elsif ( !$passwdmtime || !$shadowmtime ) {
        $shadowmtime = $passwdmtime = ( $getpwent_open_time ? $getpwent_open_time : ( stat("$SYSTEM_CONF_DIR/passwd") )[9] );

        #we did not read the shadow file so set it the same
    }

    while ( my $passwd_line = readline($getpwent_passwd_fh) ) {
        chomp $passwd_line;
        @SHAREDPW = ( split( /:/, $passwd_line ), undef );
        if ( scalar @SHAREDPW > 7 && $SHAREDPW[0] =~ m/^[A-Za-z0-9_]/ ) {    # Check for valid lines and skip commented/invalid lines
            return wantarray ? ( $SHAREDPW[0], ( $cryptpw ? $cryptpw : $SHAREDPW[1] ), $SHAREDPW[2], $SHAREDPW[3], '', '', $SHAREDPW[4], $SHAREDPW[5], $SHAREDPW[6], -1, -1, $passwdmtime, $shadowmtime ) : $SHAREDPW[0];
        }
    }
    return;
}

sub setpwent {
    if ($getpwent_passwd_fh) {
        seek( $getpwent_passwd_fh, 0, 0 ) or return undef;

        if ( eof $getpwent_passwd_fh ) {
            $isopen = 0;

            close $getpwent_passwd_fh or return undef;
            undef $getpwent_passwd_fh;
        }
    }

    return 1;
}

sub endpwent {
    if ($getpwent_passwd_fh) {
        close $getpwent_passwd_fh or return undef;
        undef $getpwent_passwd_fh;
    }

    $isopen = 0;

    return 1;
}
