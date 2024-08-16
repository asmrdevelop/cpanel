package Cpanel::Validate::Username::Mode;

# cpanel - Cpanel/Validate/Username/Mode.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Transfers::State ();

#
# This module provides an interface that abstracts out the differences between
# the cpanel-whm & pkgacct repositories.
#
my $_allows_leading_digits;

sub allows_leading_digits {
    return ( $_allows_leading_digits //= ( -e '/etc/allowstupidstuff' ? 1 : 0 ) );
}

*in_transfer_mode = *Whostmgr::Transfers::State::is_transfer;

# This function should ALWAYS return an empty list.  Do not add any entries to
# this list, ever; they should all be added to list_reserved_usernames.  This
# function only exists to support special cases in the migration pkgacct repos.
sub additional_reserved_usernames {
    return ();
}

sub _clear_cache {
    return undef $_allows_leading_digits;
}

1;
