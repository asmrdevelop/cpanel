package Cpanel::Binary;

# cpanel - Cpanel/Binary.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = 0.1;

our $gl_app;
our $gl_app_type;

# NOTE: this is an optimization to not have to do a string compare each time #
our $gl_is_binary;

BEGIN {
    # store for "posterity" #
    $gl_app = $0;

    # http://perldoc.perl.org/perlvar.html#Variables-related-to-the-interpreter-state #
    if ( $^C || $INC{'B/C.pm'} ) {
        $gl_is_binary = 1;
        $gl_app_type  = 'BINARY';
    }
    else {
        $gl_is_binary = 0;
        $gl_app_type  = 'SOURCE';
    }
}

sub app {

    # original app name #
    return $gl_app;
}

sub app_type {

    # app type string #
    return $gl_app_type;
}

sub is_binary {

    # return boolean as to whether this is a perlcc binary or not #
    return $gl_is_binary;
}

1;
