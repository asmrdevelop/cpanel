package Whostmgr::Accounts::Suspension::SSH;

# cpanel - Whostmgr/Accounts/Suspension/SSH.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Sys::Group ();

my $SUSPENSION_GROUP = 'cpanelsuspended';

=head1 NAME

Whostmgr::Accounts::Suspension::SSH - Functionality to suspend SSH access.

=head1 DESCRIPTION

This module prevents suspended accounts from proxying TCP/IP traffic through
the SSH daemon by adding these accounts to the cpanelsuspended group. This
group is denied all access in the system's sshd_config.

=head1 FUNCTIONS

=over

=item suspend( $username )

This function blocks SSH access for the specified username.

=cut

sub suspend {
    my ($username) = @_;

    my $group = Cpanel::Sys::Group->load_group_only($SUSPENSION_GROUP);
    $group->add_member($username);
    return 1;
}

=item unsuspend( $username )

The function unblocks SSH access for the specified username.

=cut

sub unsuspend {
    my ($username) = @_;

    my $group = Cpanel::Sys::Group->load_group_only($SUSPENSION_GROUP);
    $group->remove_member($username) if $group->is_member($username);
    return 1;
}

=back

=cut

1;
