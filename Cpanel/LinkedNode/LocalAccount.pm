package Cpanel::LinkedNode::LocalAccount;

# cpanel - Cpanel/LinkedNode/LocalAccount.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::LocalAccount

=head1 SYNOPSIS

    if ( Cpanel::LinkedNode::LocalAccount::local_account_does('bob', 'Mail) ) {
        # ..
    }

=head1 DESCRIPTION

This module collects pieces of logic for querying what local accounts do
vis-à-vis distribution of workloads.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::LoadCpUserFile ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $yn = local_account_does( $USERNAME, $WORKLOAD_NAME )

Returns a boolean that indicates whether $USERNAME’s $WORKLOAD_NAME services
are handled locally.

For example, C<local_account_does( 'bill', 'Mail' )> answers the question,
“Is C<bill>’s C<Mail> served locally?”

=cut

sub local_account_does ( $username, $workload ) {
    my $cpuser = Cpanel::Config::LoadCpUserFile::load($username);

    my @child_workloads = $cpuser->child_workloads();

    if (@child_workloads) {

        # Only if this is a child account that handles Web should we
        # indicate truthy.
        return grep { $_ eq $workload } @child_workloads;
    }

    require Cpanel::LinkedNode::Worker::Storage;

    # This isn’t a child account, so as long as the account lacks a worker
    # for the given workload name, assume that the local account handles
    # the workload.
    return !Cpanel::LinkedNode::Worker::Storage::read( $cpuser, $workload );
}

1;
