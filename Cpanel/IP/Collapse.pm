package Cpanel::IP::Collapse;

# cpanel - Cpanel/IP/Collapse.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub collapse {
    return $_[0] if index( $_[0], '0000:0000:0000:0000:0000:ffff:' ) != 0;
    return join( '.', unpack( 'C8', pack 'H8', substr( $_[0], 30 ) =~ tr/://dr ) );
}

1;
