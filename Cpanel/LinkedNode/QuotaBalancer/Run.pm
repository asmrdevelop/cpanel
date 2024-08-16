package Cpanel::LinkedNode::QuotaBalancer::Run;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/Run.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::Run

=head1 DESCRIPTION

This module is the main entry point into the linked-node quota balancer.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::QuotaBalancer::Backend    ();
use Cpanel::LinkedNode::QuotaBalancer::Model      ();
use Cpanel::LinkedNode::QuotaBalancer::State      ();
use Cpanel::LinkedNode::QuotaBalancer::Run::State ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $promise = run_for_users( \@USERNAMES, $OUTPUT_OBJ, %OPTS )

Starts the quota balancer for the indicated users. $OUTPUT_OBJ is a
L<Cpanel::Output> instance. %OPTS are:

=over

=item * C<verbosity> - Optional, defaults to 0. Anything truthy
currently enables extra diagnostic messages for debugging.

=back

Returns a L<Cpanel::LinkedNode::QuotaBalancer::Run::State> instance.
This object B<MUST> survive until the quota balancer is done,
or else any active subprocesses will be forcibly terminated.

Failures along the way prompt warnings.

=cut

sub run_for_users ( $users_ar, $output_obj, %opts ) {
    my $blocks_model = Cpanel::LinkedNode::QuotaBalancer::Model->new('blocks');

    my $state = Cpanel::LinkedNode::QuotaBalancer::State->new($output_obj);
    $state->set_verbose() if $opts{'verbosity'};

    # Maps an alias to an arrayref of promises, one for each user
    # that uses the associated remote. Once all of the promises finish,
    # we propagate any needed changes to that remote via a batched API call.
    my %alias_user_promises;

    for my $username ( sort @$users_ar ) {
        my $user_worker_aliases_ar;
        warn if !eval {
            $user_worker_aliases_ar = Cpanel::LinkedNode::QuotaBalancer::Backend::start_on_user( $blocks_model, $state, $username );
            1;
        };
        next if !$user_worker_aliases_ar || !@$user_worker_aliases_ar;

        my $user_done_p = Cpanel::LinkedNode::QuotaBalancer::Backend::consume_user_worker_aliases(
            blocks_model   => $blocks_model,
            state          => $state,
            username       => $username,
            worker_aliases => $user_worker_aliases_ar,
        );

        for my $alias (@$user_worker_aliases_ar) {
            push @{ $alias_user_promises{$alias} }, $user_done_p;
        }

        $user_done_p->then(
            sub {
                Cpanel::LinkedNode::QuotaBalancer::Backend::update_local_if_needed(
                    $blocks_model,
                    $state,
                    $username,
                );
            },
        );

        Cpanel::LinkedNode::QuotaBalancer::Backend::populate_models_from_state_local(
            $blocks_model,
            $state,
            $username,
        );
    }

    my $update_promise = Cpanel::LinkedNode::QuotaBalancer::Backend::update_remotes_if_needed(
        $blocks_model,
        $state,
        \%alias_user_promises,
    );

    return Cpanel::LinkedNode::QuotaBalancer::Run::State->new(
        state   => $state,
        promise => $update_promise,
    );
}

1;
