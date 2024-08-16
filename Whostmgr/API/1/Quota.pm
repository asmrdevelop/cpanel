
# cpanel - Whostmgr/API/1/Quota.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::Quota;

use strict;
use warnings;

use Cpanel::Quota::Filesys();
use Whostmgr::API::1::Utils();

use constant NEEDS_ROLE => {
    quota_enabled => undef,
};

=head1 NAME

Whostmgr::API::1::Quota

=head1 DESCRIPTION

Simple quota information WHM API

=head1 METHODS

=head2 quota_enabled

Return whether or not quotas are enabled for at least one disk configured as a home drive.

    { quota_enabled => 1 }

=cut

sub quota_enabled {
    my ( undef, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { quota_enabled => Cpanel::Quota::Filesys->new()->quotas_are_enabled() };
}

1;
