package Whostmgr::Quota::User;

# cpanel - Whostmgr/Quota/User.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Quota ();

=encoding utf-8

=head1 NAME

Whostmgr::Quota::User - Obtain quota information for a user

=head1 SYNOPSIS

    use Whostmgr::Quota::User;

    my $quota_data = Whostmgr::Quota::User::get_users_quota_data( $username, { include_mailman => 0, include_sqldbs => 0 } )

    print $quota_data->{'bytes_used'};

=head1 DESCRIPTION

This module is a wrapper around Cpanel::Quota that provides named results.

=head2 get_users_quota_data($user, $opts_ref)

=over 2

=item Input

=over 3

=item $user C<SCALAR>

    User to get the quota for.

=item $opts_ref C<HASHREF>

    - include_mailman: mailman usage will be included
    - include_sqldbs: sql database usage will be included

=back

=item Output

=over 3

=item C<HASHREF>

    The following key values pairs are returned in the hashref:

    'bytes_used'    : Number of bytes used
    'bytes_limit'   : Hard limit in bytes
    'bytes_remain'  : Number of bytes remaining
    'inodes_used'    : Number of inodes used
    'inodes_limit'   : Hard limit in inodes
    'inodes_remain'  : Number of inodes remaining


=back

=back

=cut

sub get_users_quota_data {
    my ( $user, $opts_ref ) = @_;
    my ( $used, $limit, $remain, $inodes_used, $inodes_limit, $inodes_remain ) = Cpanel::Quota::displayquota(
        {
            'user' => $user,
            bytes  => 1,
            $opts_ref ? %$opts_ref : ()
        }
    );
    $used  = 0 if length $used  && $used eq "NA\n";     # Handle legacy output from Cpanel::Quota::displayquota
    $limit = 0 if length $limit && $limit eq "NA\n";    # Legacy output from Cpanel::Quota::displayquota

    return {
        'bytes_used'    => $used,
        'bytes_limit'   => $limit,
        'bytes_remain'  => $remain,
        'inodes_used'   => $inodes_used,
        'inodes_limit'  => $inodes_limit,
        'inodes_remain' => $inodes_remain
    };
}

1;
