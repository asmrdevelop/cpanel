package Cpanel::Socket::UNIX::Micro;

# cpanel - Cpanel/Socket/UNIX/Micro.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- This code is used in dormant services:

my $MAX_PATH_LENGTH        = 107;
my $LITTLE_ENDIAN_TEMPLATE = 'vZ' . ( 1 + $MAX_PATH_LENGTH );    # x86_64 is always little endian
my $AF_UNIX                = 1;
my $SOCK_STREAM            = 1;

sub connect {
    socket( $_[0], $AF_UNIX, $SOCK_STREAM, 0 ) or warn "socket(AF_UNIX, SOCK_STREAM): $!";
    return connect( $_[0], micro_sockaddr_un( $_[1] ) );
}

sub micro_sockaddr_un {

    #pack() doesn’t check for this, so we need to:
    if ( length( $_[0] ) > $MAX_PATH_LENGTH ) {
        my $excess = length( $_[0] ) - $MAX_PATH_LENGTH;
        die "“$_[0]” is $excess character(s) too long to be a path to a local socket ($MAX_PATH_LENGTH bytes maximum)!";
    }

    # Handle abstract names.
    return pack( 'va*', $AF_UNIX, $_[0] ) if 0 == rindex( $_[0], "\0", 0 );

    return pack(
        $LITTLE_ENDIAN_TEMPLATE,    # x86_64 is always little endian
        $AF_UNIX,
        $_[0],
    );
}

sub unpack_sockaddr_un {

    # Handle abstract names.
    return substr( $_[0], 2 ) if 2 == rindex( $_[0], "\0", 2 );

    return ( unpack $LITTLE_ENDIAN_TEMPLATE, $_[0] )[1];
}

1;
