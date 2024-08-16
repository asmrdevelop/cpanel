package Cpanel::Validate::Service;

# cpanel - Cpanel/Validate/Service.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# No exceptions here to avoid pulling Cpanel::Exception & Locale
# into Chkservd.pm
use strict;
use warnings;

sub is_valid {
    return ( length $_[0] && $_[0] !~ tr{@A-Za-z0-9_-}{}c ) ? 1 : 0;
}

1;
