package Cpanel::DKIM::Propagate;

# cpanel - Cpanel/DKIM/Propagate.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Propagate - Entry point to DKIM propagations

=head1 DESCRIPTION

This module has logic to enqueue a DKIM propagation
according to need.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::LoadCpUserFile      ();
use Cpanel::LinkedNode::Worker::Storage ();

use constant _PROPAGATE_DELAY => 30;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $scheduled_yn = schedule_propagation_for_user_if_needed( $USERNAME, $DOMAIN )

If $USERNAME has a C<Mail> worker node configured,
then this will enqueue a propagation of that user’s DKIM key for $DOMAIN
to the worker node. A truthy value is returned in this case.

If the user has no C<Mail> worker node configured, a falsy value
is returned.

NB: This assumes that $USERNAME actually controls $DOMAIN. Behavior is
undefined otherwise.

=cut

sub schedule_propagation_for_user_if_needed ( $username, $domain ) {

    my $userconf      = Cpanel::Config::LoadCpUserFile::load_or_die($username);
    my $node_token_ar = Cpanel::LinkedNode::Worker::Storage::read( $userconf, 'Mail' );

    if ( my $alias = $node_token_ar && $node_token_ar->[0] ) {
        _schedule_propagation( $alias, $domain );
        return 1;
    }

    return 0;
}

=head2 $scheduled_yn = schedule_propagation_if_needed( $DOMAIN )

B<IMPORTANT:> Do not create new calls into this function. Read below.

Like C<schedule_propagation_for_user_if_needed()> but looks up $DOMAIN’s
owner rather than requiring it as a parameter. This is easier but, because
it’s more dependent on system state, also failure-prone.

=cut

sub schedule_propagation_if_needed {
    my ($domain) = @_;

    require Cpanel::LinkedNode::Worker::Domain;

    if ( my $alias = Cpanel::LinkedNode::Worker::Domain::get_worker_alias( 'Mail', $domain ) ) {
        _schedule_propagation( $alias, $domain );
        return 1;
    }

    return 0;
}

#----------------------------------------------------------------------

sub _schedule_propagation {
    my ( $alias, $domain ) = @_;

    require Cpanel::DKIM::Propagate::Data;
    require Cpanel::ServerTasks;

    Cpanel::DKIM::Propagate::Data::add(
        $alias, $domain,
        sub {
            Cpanel::ServerTasks::schedule_task( ['DKIMTasks'], _PROPAGATE_DELAY(), 'propagate_dkim_to_worker_nodes' );
        },
    );

    return;
}

1;
