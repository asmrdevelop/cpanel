package Cpanel::LinkedNode::QuotaBalancer::Backend;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::Backend

=head1 DESCRIPTION

This module contains miscellaneous individually testable functions
for the quota balancer. It’s not really meant for use outside
that context; if you find something here of interest for something
other than the quota balancer, please refactor it to a more
general-use namespace.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Promise::XS ();

use Cpanel::Imports;

use Cpanel::ArrayFunc::Uniq            ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::Math                       ();
use Cpanel::Quota::Blocks              ();
use Cpanel::Quota::Common              ();
use Whostmgr::API::1::Utils::Batch     ();

# accessed in tests
our $_EDITQUOTA_BATCH_SIZE = 200;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $aliases_ar = start_on_user( $BLOCKS_MODEL, $INODES_MODEL, $USERNAME )

Fetches the user’s cpuser data and determines quota and worker node
configuration. Populates $BLOCKS_MODEL and $INODES_MODEL (instances of
L<Cpanel::LinkedNode::QuotaBalancer::Model>) accordingly.

If the user has a blocks quota set then an array reference
of aliases of the user’s worker nodes is returned. If the user has no
worker nodes, of course, that array will be empty.

If the user has no quotas, undef is returned.

=cut

sub start_on_user ( $blocks_model, $state, $username ) {
    my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    my @worker_data = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser);

    # Ignore combined accounts.
    if ( !@worker_data ) {
        $state->debug( locale()->maketext( "“[_1]” is a combined account.", $username ) );
        return undef;
    }

    my $has_quota;

    if ( my $num = $cpuser->{'DISK_BLOCK_LIMIT'} ) {
        $blocks_model->set_user_limit( $username, $num );
        $has_quota = 1;
    }

    # If the user has no disk usage quotas then we’re done here.
    if ( !$has_quota ) {
        $state->debug( locale()->maketext( "“[_1]” has no limit on disk blocks usage.", $username ) );

        return undef;
    }

    my @aliases = Cpanel::ArrayFunc::Uniq::uniq( sort map { $_->{'alias'} } @worker_data );

    return \@aliases;
}

#----------------------------------------------------------------------

=head2 consume_user_worker_aliases( %OPTS )

Starts a fetch of a given user’s disk quota usage on the user’s workers.

Returns a promise that resolves when that work is done.

%OPTS are:

=over

=item * C<blocks_model> - L<Cpanel::LinkedNode::QuotaBalancer::Model> instance

=item * C<state> - L<Cpanel::LinkedNode::QuotaBalancer::State> instance

=item * C<username> - the name of the user at hand

=item * C<worker_aliases> - An array reference of aliases of the user’s workers.

=back

=cut

sub consume_user_worker_aliases (%opts) {
    my ( $blocks_model, $state, $username, $user_worker_aliases_ar ) = @opts{ 'blocks_model', 'state', 'username', 'worker_aliases' };

    # This promise resolves when all of the user’s aliases’
    # disk usages are fetched.
    my $user_done_d = Promise::XS::deferred();

    my @alias_promises;

    for my $alias (@$user_worker_aliases_ar) {

        push @alias_promises, $state->get_remote_user_disk_usage_p( $alias, $username )->then(
            sub ($usage_hr) {
                if ( $blocks_model->get_user_limit($username) ) {

                    # If the remote has quotas off then blocks_used will
                    # be undef. Treat this the same as 0 so we just ignore
                    # that node for the purposes of distributing quota.
                    $blocks_model->set_remote_user_used( $alias, $username, $usage_hr->{'blocks_used'} // 0 );

                    $blocks_model->set_remote_user_limit( $alias, $username, $usage_hr->{'blocks_limit'} // 0 );
                }
            }
        );
    }

    Promise::XS::all(@alias_promises)->then(
        sub { $user_done_d->resolve(@_) },
        sub { $user_done_d->reject(@_) },
    );

    return $user_done_d->promise();
}

#----------------------------------------------------------------------

=head2 populate_models_from_state_local( $BLOCKS_MODEL, $INODES_MODEL, $STATE, $USERNAME )

Inputs are as described for the corresponding inputs to
C<consume_user_worker_aliases()>.

Copies $USERNAME’s local quota information from $STATE into
$BLOCKS_MODEL and $INODES_MODEL.

Returns nothing.

=cut

sub populate_models_from_state_local ( $blocks_model, $state, $username ) {
    if ( $blocks_model->get_user_limit($username) ) {
        my $local_blocks_used = $state->get_local_user_blocks_used($username);
        $blocks_model->set_local_user_used( $username, $local_blocks_used );

        my $local_blocks_limit = $state->get_local_user_blocks_limit($username);
        $blocks_model->set_local_user_limit( $username, $local_blocks_limit );
    }

    return;
}

#----------------------------------------------------------------------

=head2 update_local_if_needed( $BLOCKS_MODEL, $STATE, $USERNAME )

Saves local quota changes if the given
L<Cpanel::LinkedNode::QuotaBalancer::Model> instances indicate is
necessary for $USERNAME.

Returns nothing; warns on failure.

=cut

sub update_local_if_needed ( $blocks_model, $state, $username ) {
    my $indent = $state->is_verbose() && do {
        $state->debug( locale()->maketext( "Checking user “[_1]” …", $username ) );

        $state->create_log_level_indent();
    };

    if ( !$blocks_model->get_user_limit($username) || !$blocks_model->user_needs_update($username) ) {
        $state->debug( locale()->maketext("No quota rebalance needed.") );
        return;
    }

    if ( $state->is_verbose() ) {
        $state->info( locale()->maketext("Quota rebalance needed.") );
    }
    else {
        $state->info( locale()->maketext( "Quota rebalance needed: “[_1]”", $username ) );
    }

    my $indent2 = $state->create_log_level_indent();

    my $limit = $blocks_model->get_user_limit($username);

    $state->info( locale()->maketext( "Total blocks allowed: [numf,_1]", $limit ) );

    _display_current_used_and_limit(
        $state,
        locale()->maketext("Local quota usage"),
        $blocks_model->get_local_user_used($username),
        $blocks_model->get_local_user_limit($username),
    );

    for my $alias ( @{ $blocks_model->get_user_worker_aliases($username) } ) {
        _display_current_used_and_limit(
            $state,
            locale()->maketext( "“[_1]” quota usage", $state->get_worker_hostname($alias) ),
            $blocks_model->get_remote_user_used( $alias, $username ),
            $blocks_model->get_remote_user_limit( $alias, $username ),
        );
    }

    my $blocks_limits = $blocks_model->compute_user_limits($username);

    # Duplicate so we can mutate in peace:
    $blocks_limits = {%$blocks_limits};

    my $local_blocks = delete $blocks_limits->{'/'};

    $state->info( locale()->maketext( "New local quota: [numf,_1]", $local_blocks ) );

    for my $alias ( @{ $blocks_model->get_user_worker_aliases($username) } ) {
        my $hostname = $state->get_worker_hostname($alias);
        $state->info( locale()->maketext( "New quota for “[_1]”: [numf,_2]", $hostname, $blocks_limits->{$alias} ) );
    }

    try {

        # NB: We avoid Whostmgr::Quota here because we need to leave
        # the controller cpuser’s DISK_BLOCK_LIMIT in place.
        my $quota = Cpanel::Quota::Blocks->new(
            {
                user           => $username,
                skip_conf_edit => 1,
            }
        );

        $quota->set_limits_if_quotas_enabled(
            {
                soft => $local_blocks,
                hard => $local_blocks,
            }
        );
    }
    catch {
        warn "Failed to update $username’s local quota: $_";
    };

    return;
}

sub _display_current_used_and_limit ( $state, $label, $used, $limit ) {
    my $msg;

    if ($limit) {
        $msg = sprintf(
            "%s: %s / %s (%s%%)",
            $label,
            map { locale()->numf($_) } (
                $used,
                $limit,
                sprintf( '%.02f', 100 * $used / $limit ),
            ),
        );
    }
    else {
        $msg = sprintf(
            "%s: %s / ∞",
            $label,
            locale()->numf($used),
        );
    }

    $state->info($msg);

    return;
}

#----------------------------------------------------------------------

=head2 $promise = update_remotes_if_needed( $BLOCKS_MODEL, $STATE, \%ALIAS_USER_PROMISES )

Called after $BLOCKS_MODEL (instance of
L<Cpanel::LinkedNode::QuotaBalancer::Model>) is populated.
Sends quota updates to remotes.

$STATE is a L<Cpanel::LinkedNode::QuotaBalancer::State> instance.
Entries of %ALIAS_USER_PROMISES are ( $alias => \@promises ), where $alias
is the alias of one of the system’s linked/worker nodes, and each
@promises member represents completion of the fetches for one user’s
data. Once all @promises are finished, the associated linked/worker node
can have quota updates pushed out.

The return is a promise that resolves when all update operations are finished.
This promise never rejects.

=cut

sub update_remotes_if_needed ( $blocks_model, $state, $alias_user_promises ) {    ## no critic qw(ManyArgs) - mis-parse

    # Assume the following users:
    #
    #   bob: uses workers server1 and server2
    #   jane: uses server1 only
    #   pat: uses server2 only
    #
    #   linda: uses server3 only
    #   danny: uses server3 only
    #
    # We want to batch all of the updates to both server1 and server2.
    # But because server1 and server2 share users, we have to wait until
    # they’re both done to send updates to either of them.
    #
    # We make this happen by making each user’s promise depend on the
    # quota-fetch from the user’s servers, thus:
    #
    #   bob: promise resolves when fetches from server1 & server2 are done
    #   jane: promise resolves when fetch from server1 is done
    #   pat: promise resolves when fetch from server2 is done
    #
    #   user-promises for server1: bob & jane
    #   user-promises for server2: bob & pat
    #
    # linda & danny on server3 are in a bit different setup: server3 doesn’t
    # share any users with other servers, so as soon as server3’s fetch is done
    # we’ll send update requests to server 3. The same logic as described above
    # makes this “just work”:
    #
    #   linda: promise resolves when fetch from server3 is done
    #   danny: promise resolves when fetch from server3 is done
    #
    #   user-promises for server3: linda & danny

    # This array’s promises should always resolve.
    my @update_promises;

    for my $alias ( keys %$alias_user_promises ) {
        my $alias_done_p = Promise::XS::all( @{ $alias_user_promises->{$alias} } );

        my $node_obj = $state->get_linked_nodes()->{$alias} or do {
            die "No linked node “$alias” exists!";
        };

        my $hostname = $node_obj->hostname();

        my $update_p = $alias_done_p->then(
            sub {
                my @calls;

                # Either model object should return the same number of users.
                my @usernames = @{ $blocks_model->get_remote_usernames($alias) };

                for my $username ( sort @usernames ) {
                    my %api_args = _determine_user_editquota_args( $blocks_model, $state, $alias, $username );

                    if (%api_args) {
                        push @calls, [ editquota => \%api_args ];
                    }
                }

                return if !@calls;

                $state->info( locale()->maketext( "Updating “[_1]” …", $hostname ) );

                # All of these must resolve.
                my @request_promises = _generate_final_request_promises(
                    $state,
                    $node_obj,
                    \@calls,
                );

                # Always resolves because all @request_promises always resolve.
                return Promise::XS::all(@request_promises);
            }
        );

        push @update_promises, $update_p;
    }

    # Always resolves because all @update_promises always resolve.
    return Promise::XS::all(@update_promises);
}

sub _generate_final_request_promises ( $state, $node_obj, $calls_ar ) {
    my @request_promises;

    my $hostname = $node_obj->hostname();

    while ( my @chunk = splice( @$calls_ar, 0, $_EDITQUOTA_BATCH_SIZE ) ) {
        my $batch_hr = Whostmgr::API::1::Utils::Batch::assemble_batch(
            @chunk,
        );

        my $in_child_cr = sub {
            my $api_obj = $node_obj->get_remote_api();

            $api_obj->request_whmapi1_or_die( batch => $batch_hr );

            return;
        };

        # The new promise will always resolve.
        push @request_promises, $state->do_in_child_p($in_child_cr)->then(
            sub {
                $state->info( locale()->maketext( "“[_1]” updated [quant,_2,user’s quota,users’ quotas].", $hostname, 0 + @chunk ) );

                return;
            },

            sub ($why) {

                $state->warn( locale()->maketext( "“[_1]” failed to update [quant,_2,user’s quota,users’ quotas] because an error occurred: [_3]", $hostname, 0 + @chunk, $why ) );
            }
        );
    }

    return @request_promises;
}

# Returns a list of key/value pairs for an “editquota” API call.
# If the list is empty, that indicates to forgo the API call.
sub _determine_user_editquota_args ( $blocks_model, $state, $worker_alias, $username ) {    ## no critic qw(ManyArgs) - mis-parse
    my %args;

    _determine_args_for_model(
        model        => $blocks_model,
        state        => $state,
        worker_alias => $worker_alias,
        username     => $username,
        args_hr      => \%args,
    );

    if (%args) {
        $args{'quota'} /= $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS;

        # The “editquota” API requires a whole number.
        # We never want to set a quota of 0, so we always round up.
        #
        $args{'quota'} = Cpanel::Math::ceil( $args{'quota'} );

        $args{'user'} = $username;
    }

    return %args;
}

sub _determine_args_for_model (%opts) {
    my ( $model, $state, $username, $args_hr ) = @opts{ 'model', 'state', 'username', 'args_hr' };

    my $lh = locale();

    if ( $model->user_needs_update($username) ) {
        my $comp       = $model->compute_user_limits($username);
        my $new_blocks = $comp->{ $opts{'worker_alias'} };

        $args_hr->{'quota'} = $new_blocks;
    }

    return;
}

1;
