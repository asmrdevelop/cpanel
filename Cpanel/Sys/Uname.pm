package Cpanel::Sys::Uname;

# cpanel - Cpanel/Sys/Uname.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $SYS_UNAME       = 63;
our $UNAME_ELEMENTS  = 6;
our $_UTSNAME_LENGTH = 65;
my $UNAME_PACK_TEMPLATE   = ( 'c' . $_UTSNAME_LENGTH ) x $UNAME_ELEMENTS;
my $UNAME_UNPACK_TEMPLATE = ( 'Z' . $_UTSNAME_LENGTH ) x $UNAME_ELEMENTS;

my @uname_cache;

sub get_uname_cached {
    return ( @uname_cache ? @uname_cache : ( @uname_cache = syscall_uname() ) );
}

sub clearcache {
    @uname_cache = ();
    return;
}

sub syscall_uname {
    my $uname;
    if ( syscall( $SYS_UNAME, $uname = pack( $UNAME_PACK_TEMPLATE, () ) ) == 0 ) {
        return unpack( $UNAME_UNPACK_TEMPLATE, $uname );
    }
    else {
        die "The uname() system call failed because of an error: $!";
    }
    return;
}
1;
