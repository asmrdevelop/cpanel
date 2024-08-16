package Cpanel::StringFunc::Case;

# cpanel - Cpanel/StringFunc/Case.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.2';

# DO NOT OPTIMIZE THIS FUNCTION TO ALTER $_ that is passed in
sub ToUpper {
    return unless defined $_[0];
    ( local $_ = $_[0] ) =~ tr/a-z/A-Z/;    # avoid altering $_[0] by making a copy
    return $_;
}

# DO NOT OPTIMIZE THIS FUNCTION TO ALTER $_ that is passed in
sub ToLower {
    return unless defined $_[0];
    ( local $_ = $_[0] ) =~ tr/A-Z/a-z/;    # avoid altering $_[0] by making a copy
    return $_;
}
1;
