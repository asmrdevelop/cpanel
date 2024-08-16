package Whostmgr::Accounts::Suspension::WorkerNodes;

# cpanel - Whostmgr/Accounts/Suspension/WorkerNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Suspension::WorkerNodes

=head1 DESCRIPTION

Suspend and unsuspend an account’s remote worker nodes.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Worker::GetAll  ();
use Cpanel::LinkedNode::Worker::Storage ();
use Cpanel::Config::LoadCpUserFile      ();
use Cpanel::LinkedNode::RemoteAPI       ();
use Whostmgr::Accounts::SuspensionData  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 suspend($USERNAME)

Suspends remote accounts. The reason and reseller-lock properties
will be copied from the local host.

=cut

sub suspend ($username) {
    my $reason = Whostmgr::Accounts::SuspensionData->get_reason($username);
    my $locked = Whostmgr::Accounts::SuspensionData->locked($username);

    _do_task(
        $username,

        suspendacct => {
            user       => $username,
            reason     => $reason,
            disallowun => $locked,
        },
    );

    return;
}

=head2 unsuspend($USERNAME)

Unsuspends remote accounts.

=cut

sub unsuspend ($username) {

    _do_task(
        $username,

        unsuspendacct => { user => $username },
    );

    return;
}

# When/if this supports multiple workers per user, we’ll need
# to bring in Cpanel::CommandQueue or something similar so that
# we always (attempt to) leave all workers in the same state.
# For now, though, since we only have 1 worker type we can just
# do our 1 thing.
#
sub _do_task ( $username, $do_fn, $arguments_hr ) {
    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    my @types = Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES();

    die "I only understand 1 worker type!" if @types > 1;

    for my $type (@types) {
        my $alias_token_ar = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_data, 'Mail' );

        next if !$alias_token_ar;

        my $alias = $alias_token_ar->[0];

        my $api = Cpanel::LinkedNode::RemoteAPI::create_whmapi1($alias);

        my $result = $api->request_whmapi1( $do_fn, $arguments_hr );

        # TODO: Needs better reporting
        die $result->get_error() if $result->get_error();
    }

    return;
}

1;
