package Cpanel::ChangePasswd::DigestAuth;

# cpanel - Cpanel/ChangePasswd/DigestAuth.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Auth::Digest::DB::Manage ();

sub process {
    my %OPTS = @_;

    if ( $OPTS{'optional_services'}->{'digest'} ) {
        Cpanel::Auth::Digest::DB::Manage::set_password( $OPTS{'user'}, $OPTS{'newpass'} );
    }
    else {
        Cpanel::Auth::Digest::DB::Manage::remove_entry( $OPTS{'user'} );
    }
}

1;
