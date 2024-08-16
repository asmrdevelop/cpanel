package Cpanel::Quota::Reboot;

# cpanel - Cpanel/Quota/Reboot.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Quota::Reboot - Functions to determine if a reboot is needed after enabling quotas

=head1 SYNOPSIS

    use Cpanel::Quota::Reboot;

    my $needs_reboot_after_turning_on_quota = Cpanel::Quota::Reboot::needs_reboot_after_turning_on_quota();

=head2 needs_reboot_after_turning_on_quota()

Returns 1 if the system needs to reboot after turning on quota

Returns 0 if the system does not need to reboot after turning on quota

=cut

sub needs_reboot_after_turning_on_quota_xfs {
    require Cpanel::Filesys::Mount;

    return Cpanel::Filesys::Mount::are_xfs_mounts_on_system() ? 1 : 0;
}

1;
