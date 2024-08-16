package Cpanel::Proc::Basename;

# cpanel - Cpanel/Proc/Basename.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub getbasename {
    my ($name) = @_;

    return '' if !length $name;

    $name = ( split( /\s+/, $name ) )[0] if $name =~ tr{ \t\r\n}{};

    if ( index( $name, '/' ) == 0 ) {
        return ( split( '/', $name ) )[-1];
    }
    else {
        return $name;
    }
}

1;
