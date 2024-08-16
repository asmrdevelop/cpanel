
# cpanel - Cpanel/Quota/Normalized.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Normalized;

use strict;
use warnings;

use Quota ();

use constant {
    _ENOENT => 2,
    _ESRCH  => 3
};

=head1 NAME

Cpanel::Quota::Normalized

=head1 DESCRIPTION

This module is intended to be a wrapper around the Quota
module to normalize the output from its functions so it behaves
the same reguardless of the underlying filesystem.

For Example:

On XFS quotactl will return ENOENT for a non-existant uid
quotactl(Q_XGETQUOTA|USRQUOTA, "/dev/mapper/centos_centos--7--clone-root", 5020, 0x7ffd381e09b8) = -1 ENOENT (No such file or directory)

On ext4 quotactl will return all 0s for a non-existant uid
quotactl(Q_XGETQUOTA|USRQUOTA, "/dev/mapper/centos_centos--7--clone-root", 1, {version=1, flags=XFS_USER_QUOTA, fieldmask=0, id=1, blk_hardlimit=0, blk_softlimit=0, ino_hardlimit=0, ino_softlimit=0, bcount=93560, icount=62, ...}) = 0

=head1 SYNOPSIS

  my @results = Cpanel::Quota::Normalized::query('(XFS)/dev/mapper/centos_centos--7--clone-root', 5020);

  my @results = Cpanel::Quota::Normalized::query('/dev/ext3device', 5020);

=cut

=head1 METHODS

=head2 query()

This is a wrapper around Query::query that makes XFS calls
behave like calls to any other filesystem

=head3 Arguments

See Quota::query

=head3 Return Value

See Quota::query

=cut

sub query {
    my ( $device, @args ) = @_;

    local $!;
    my @result = Quota::query( $device, @args );

    if ( !@result && index( $device, '(XFS)' ) == 0 && $! == _ENOENT ) {
        return ( (0) x 8 );
    }

    # Quotas are explictly disabled or not setup (quotaoff)
    if ( $! == _ESRCH ) {
        return ( (0) x 8 );
    }

    return @result;
}

1;
