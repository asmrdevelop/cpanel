package Cpanel::SafeFind;

# cpanel - Cpanel/SafeFind.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.2';

use File::Find ();    # no need to do a lazy load, this is now a core module

sub find {
    return if grep ( /\0/, @_[ 1 .. $#_ ] );
    goto &File::Find::find;
}

sub finddepth {
    return if grep ( /\0/, @_[ 1 .. $#_ ] );
    goto &File::Find::finddepth;
}

1;
