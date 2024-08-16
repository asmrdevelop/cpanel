package Cpanel::LinkedNode::QuotaBalancer::State;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/State.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::State

=head1 DESCRIPTION

This module maintains the quota balancer’s cached application state.
It doesn’t do any interesting calculations; for that, see
L<Cpanel::LinkedNode::QuotaBalancer::Model>.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Output::Container::MethodProvider );

use Try::Tiny;

use Promise::XS ();

use Cpanel::Imports;

use Cpanel::Async::Forker           ();
use Cpanel::Exception               ();
use Cpanel::LinkedNode::Index::Read ();
use Cpanel::LinkedNode::Worker::WHM ();
use Cpanel::SysQuota                ();

#----------------------------------------------------------------------

=head1 SYNCHRONOUS METHODS

The following return values immediately:

=head2 $obj = I<CLASS>->new( $OUTPUT_OBJ )

Instantiates this class. $OUTPUT_OBJ is an instance of L<Cpanel::Output>
(probably a subclass thereof, e.g., L<Cpanel::Output::Formatted::Terminal>).

=cut

sub new ( $class, $output_obj ) {
    my %self = ( _logger => $output_obj );

    return bless \%self, $class;
}

=head2 $obj = I<OBJ>->set_verbose()

Enables verbose logging.

=cut

sub set_verbose ($self) {
    $self->{'_verbose'} = 1;

    return $self;
}

=head2 $yn = I<OBJ>->is_verbose()

Returns a boolean that indicates whether I<OBJ>’s verbose logging
is enabled.

=cut

sub is_verbose ($self) {
    return $self->{'_verbose'} ? 1 : 0;
}

=head2 $yn = I<OBJ>->debug( $MSG )

Logs $MSG, but only if I<OBJ>’s verbose logging is enabled.

=cut

sub debug ( $self, $msg ) {
    $self->info($msg) if $self->{'_verbose'};

    return;
}

#----------------------------------------------------------------------

=head2 $nodes_hr = I<OBJ>->get_linked_nodes()

Returns the cached results from L<Cpanel::LinkedNode::Index::Read>’s
C<get()> function.

=cut

sub get_linked_nodes ($self) {
    return $self->{'_linked_nodes'} ||= Cpanel::LinkedNode::Index::Read::get();
}

=head2 $hostname = I<OBJ>->get_worker_hostname( $ALIAS )

Returns the hostname of a worker node identified via its $ALIAS.

=cut

sub get_worker_hostname ( $self, $alias ) {
    return $self->get_linked_nodes()->{$alias}->hostname();
}

#----------------------------------------------------------------------

=head2 $number = I<OBJ>->get_local_user_blocks_used( $USERNAME )

Returns $USERNAME’s local blocks used (as reported by the system’s quotas).

=cut

sub get_local_user_blocks_used ( $self, $username ) {
    $self->_ensure_quota_analysis();

    return $self->{'_blocks_used'}{$username};
}

=head2 $number = I<OBJ>->get_local_user_blocks_limit( $USERNAME )

Like C<get_local_user_blocks_used()> but returns the blocks limit.
If there’s no such limit, 0 is returned.

=cut

sub get_local_user_blocks_limit ( $self, $username ) {
    $self->_ensure_quota_analysis();

    return $self->{'_blocks_limit'}{$username} // 0;
}

#----------------------------------------------------------------------

=head1 ASYNCHRONOUS METHODS

The following return promises:

=head2 promise(@return) = I<OBJ>->do_in_child_p( $CODEREF )

Executes $CODEREF in a child process and resolves with the result.

This uses L<Cpanel::Async::Forker> internally and is subject to that
module’s limitations; see its documentation for more details.

=cut

sub do_in_child_p ( $self, $cr ) {
    my $forker = $self->{'_forker'} ||= Cpanel::Async::Forker->new();

    return $self->{'_forker'}->do_in_child(
        sub (@args) {
            my $ret;

            try {
                $ret = $cr->(@args);
            }
            catch {

                # Prevent a stack trace.
                die Cpanel::Exception::get_string($_);
            };
        }
    );
}

=head2 promise($usage_hr) = I<OBJ>->get_remote_user_disk_usage_p( $ALIAS, $USERNAME )

Fetches $USERNAME’s quota information from the linked node with alias $ALIAS.
This method’s return value is a promise that resolves to the appropriate hash
reference from the result of a call to WHM API v1’s
L<get_disk_usage|https://go.cpanel.net/whm_get_disk_usage> function.

=cut

sub get_remote_user_disk_usage_p ( $self, $alias, $username ) {
    my $API_FN = 'get_disk_usage';

    my $hostname = $self->get_worker_hostname($alias);

    my $p = $self->{'_disk_usage_promise'}{$alias} ||= do {
        my $node_obj = $self->get_linked_nodes()->{$alias} || do {
            return Promise::XS::rejected("No linked node “$alias” exists!");
        };

        $self->debug( locale()->maketext( "[_1]: Sending “[_2]” query …", $hostname, $API_FN ) );

        my $pp = $self->do_in_child_p(
            sub {
                my $resp = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => $API_FN,
                    api_opts => { cache_mode => 'off' },
                );

                return _xform_get_disk_usage_data_to_hr($resp);
            }
        );

        $pp->then(
            sub {
                $self->debug( locale()->maketext( "[_1]: Received “[_2]” response.", $hostname, $API_FN ) );
            }
        );

        $pp;
    };

    return $p->then(
        sub ($user_usage_hr) {
            my $usage_hr = $user_usage_hr->{$username} or do {
                die "$API_FN on “$alias” lacks “$username”!";
            };

            return $usage_hr;
        }
    );
}

#----------------------------------------------------------------------

sub _ensure_quota_analysis ($self) {
    if ( !$self->{'_blocks_used'} ) {
        my @pieces = Cpanel::SysQuota::analyzerepquotadata();

        # NB: Indexes 3 & 4 are inodes used/limit.
        @{$self}{ '_blocks_used', '_blocks_limit' } = @pieces[ 0, 1 ];
    }

    return;
}

sub _xform_get_disk_usage_data_to_hr ($resp_data) {
    my %user_usage = map { $_->{'user'} => $_ } @$resp_data;

    return \%user_usage;
}

1;
