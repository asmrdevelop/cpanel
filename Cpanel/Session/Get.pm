package Cpanel::Session::Get;

# cpanel - Cpanel/Session/Get.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Rand::Get       ();
use Cpanel::Config::Session ();

our $VERSION = 1.2;

our $SESSION_LENGTH = 16;

sub getsessionname {
    my $user        = shift || '';
    my $tag         = shift || '';
    my $randsession = $user . ':' . Cpanel::Rand::Get::getranddata( $SESSION_LENGTH, undef, 10 ) . ( $tag ? ":$tag" : '' );
    while ( -e $Cpanel::Config::Session::SESSION_DIR . '/raw/' . $randsession ) {
        $randsession = $user . ':' . Cpanel::Rand::Get::getranddata( $SESSION_LENGTH, undef, 10 ) . ( $tag ? ":$tag" : '' );
    }
    return $randsession;
}

1;
