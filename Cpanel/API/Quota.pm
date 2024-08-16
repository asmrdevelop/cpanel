
# cpanel - Cpanel/API/Quota.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::Quota;

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings) -- not fully vetted for warnings

use Cpanel::Math::Bytes                ();
use Cpanel::Quota                      ();
use Cpanel::Quota::Constants           ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::LinkedNode::Worker::User   ();
use Cpanel::Locale 'lh';

=head1 UAPI documentation

Quota

=head1 Functions

=head2 get_quota_info

=head3 Description

Looks up and returns quota information for the current cPanel user.

=head3 Parameters

n/a

=head3 Returns

This function returns a hash with the following keys:

       megabytes_used - (float) The number of megabytes used.
      megabyte_limit - (float) The megabyte limit. (If 0.0, then unlimited.)
     megabytes_remain - (float) Megabytes remaining. (If unlimited, then this is irrelevant.)
          inodes_used - (integer) The number of files used (actually inodes).
         inode_limit  - (integer) The inode limit.
        inodes_remain - (integer) Inodes remaining. (If unlimited, then this is irrelevant.)
 under_megabyte_limit - (boolean) Whether the account is under its megabyte limit.
    under_inode_limit - (boolean) Whether the account is under its inode quota.
  under_quota_overall - (boolean) Whether the account is under its quota overall. This is only true if neither the megabyte nor inode quota has been met.

In this context, megabyte should be taken to mean mebibyte. That is, 1048576 bytes, not 1000000 bytes.

=cut

sub get_quota_info {
    my ( $args, $result ) = @_;

    my $byte_limit = ( $Cpanel::CPDATA{'DISK_BLOCK_LIMIT'} || 0 ) * Cpanel::Quota::Constants::BYTES_PER_BLOCK();

    my $inode_limit = $Cpanel::CPDATA{'DISK_INODE_LIMIT'} || 0;

    my ( $bytes_used, $inodes_used );

    my @displayquota_response = Cpanel::Quota::displayquota(1);

    if ( 6 == @displayquota_response ) {
        ( $bytes_used, undef, undef, $inodes_used, my $inode_limit2 ) = @displayquota_response;

        # At least one cP customer who uses inode quotas forgoes setting
        # the limit in the cpuser file and alters the quota system directly.
        # Let’s accommodate that.
        $inode_limit ||= $inode_limit2;
    }
    elsif ( 1 == @displayquota_response && $displayquota_response[0] =~ /^NA/ ) {    # Note: This NA will have a trailing newline

        # quotas are not enabled for this filesystem, so there is no real information to report
    }
    else {
        die lh()->maketext('The system failed to retrieve the filesystem quota information.');
    }

    $_ ||= 0 for ( $bytes_used, $inodes_used );

    my @workers = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser( \%Cpanel::CPDATA );

    for my $worker_hr (@workers) {
        my $this_result = Cpanel::LinkedNode::Worker::User::call_worker_uapi(
            $worker_hr->{'worker_type'},
            'Quota',
            'get_local_quota_info',
        );

        if ( $this_result->status() ) {
            $bytes_used += $this_result->data()->{'bytes_used'};

            $inodes_used += $this_result->data()->{'inodes_used'};
        }
        else {
            $result->raw_warning( "$worker_hr->{'alias'}: " . $this_result->errors_as_string() );
        }
    }

    my $under_megabyte_limit = ( !$byte_limit  || $bytes_used < $byte_limit )   || 0;
    my $under_inode_limit    = ( !$inode_limit || $inodes_used < $inode_limit ) || 0;
    my $under_quota          = ( $under_megabyte_limit && $under_inode_limit );

    my $megabytes_used = $bytes_used && 0 + Cpanel::Math::Bytes::to_mib($bytes_used);
    my $megabyte_limit = $byte_limit && 0 + Cpanel::Math::Bytes::to_mib($byte_limit);

    my $megabytes_remain;
    if ( $byte_limit && $bytes_used <= $byte_limit ) {
        $megabytes_remain = 0 + Cpanel::Math::Bytes::to_mib( $byte_limit - $bytes_used );
    }

    my $inodes_remain = $inode_limit && ( $inode_limit - $inodes_used );

    $result->data(
        {
            # basic summary duplicating what displayquota gives
            megabytes_used   => $megabytes_used   || '0.00',
            megabyte_limit   => $megabyte_limit   || '0.00',
            megabytes_remain => $megabytes_remain || '0.00',
            inodes_used      => $inodes_used      || '0',
            inode_limit      => $inode_limit      || '0',
            inodes_remain    => $inodes_remain    || '0',

            # convenience answers
            under_megabyte_limit => $under_megabyte_limit,
            under_inode_limit    => $under_inode_limit,
            under_quota_overall  => $under_quota,
        }
    );

    return 1;
}

sub get_local_quota_info ( $args, $result, @ ) {
    my @resp = Cpanel::Quota::displayquota(1);

    if ( $resp[0] && 0 == rindex( $resp[0], 'NA', 0 ) ) {
        @resp = ();
    }

    $result->data(
        {
            bytes_used => $resp[$Cpanel::Quota::SPACE_USED],
            byte_limit => $resp[$Cpanel::Quota::SPACE_LIMIT],

            inodes_used => $resp[$Cpanel::Quota::INODES_USED],
            inode_limit => $resp[$Cpanel::Quota::INODES_LIMIT],
        }
    );

    return 1;
}

our %API = (
    get_quota_info       => { allow_demo => 1 },
    get_local_quota_info => { allow_demo => 1 },
);

1;
