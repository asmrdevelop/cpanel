package Cpanel::Validate::ResourceLimit;

# cpanel - Cpanel/Validate/ResourceLimit.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub resource_limit_normalization {
    my ($max_limit) = @_;

    return 'unlimited' if ( !length $max_limit || $max_limit =~ m/unlimited/i );
    return int $max_limit;
}

sub validate_resource_limit {
    my ( $max_limit, $current_total ) = @_;

    # if the max limit is unlimited, another won't hurt
    return 1 if $max_limit eq 'unlimited';

    # if the max limit is greater than the current total, one more will be ok
    return 1 if $max_limit > $current_total;

    # otherwise, we can't create any more
    return 0;
}

1;
