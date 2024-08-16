package Cpanel::Quota::OverCache::Check;

# cpanel - Cpanel/Quota/OverCache/Check.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Quota::Overcache::Check - A cache for whether a user is over quota.

=cut

use strict;
use warnings;

use Cpanel::Autodie ();

our $_DIR = '/var/cpanel/overquota';

sub user_is_at_blocks_quota {
    my ($username) = @_;

    #Just in case.
    _check_username($username);

    return ( Cpanel::Autodie::exists_nofollow("$_DIR/blocks_$username") ? 1 : 0 );
}

sub _check_username {
    my ($username) = @_;

    die "Unsafe username!! ($username)" if -1 != index( $username, '/' );

    return;
}

1;
