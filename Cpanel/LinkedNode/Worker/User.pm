package Cpanel::LinkedNode::Worker::User;

# cpanel - Cpanel/LinkedNode/Worker/User.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::User

=head1 SYNOPSIS

    my $hn_tk_ar = Cpanel::LinkedNode::Worker::User::get_hostname_and_token('Mail');

    # The same pattern goes for call_worker_api2().
    my $result_or_undef = Cpanel::LinkedNode::Worker::User::call_worker_uapi(
        'Mail',
        'Email',
        'list_pops',
        \%args,
    );

=head1 DESCRIPTION

This module contains logic for a user process (i.e., running under cPanel)
to interact with worker nodes.

B<IMPORTANT:> The functions in this module require that the L<Cpanel>
module’s globals be set.

=cut

#----------------------------------------------------------------------

use Cpanel                              ();
use Cpanel::Context                     ();
use Cpanel::LinkedNode::User            ();
use Cpanel::LinkedNode::Worker::Storage ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $result_or_undef = call_worker_uapi( $WORKER_TYPE, $MOD, $FN, \%ARGS )

Retrieves the user’s worker node configuration for the given $WORKER_TYPE.

If such configuration exists, calls UAPI on that worker node with
the given $MOD (module), $FN (function), and %ARGS. The function’s return
is a L<Cpanel::Result> instance that represents the response to that
UAPI call. (See L<Cpanel::LinkedNode::Worker::cPanel> for more details.)

If the user has no worker node of type $WORKER_TYPE configured, then
this function returns undef.

=cut

sub call_worker_uapi {
    my ( $worker_type, $module, $fn, $args_hr ) = @_;

    return _call( 'call_uapi', $worker_type, $module, $fn, $args_hr );
}

sub _call {
    my ( $api_fn, $worker_type, $module, $fn, $args_hr ) = @_;

    my $alias_and_token_ar = get_alias_and_token($worker_type);

    return $alias_and_token_ar && do {
        my ( $alias, $token ) = @$alias_and_token_ar;

        require Cpanel::LinkedNode::Worker::cPanel;

        Cpanel::LinkedNode::Worker::cPanel->can($api_fn)->(
            username     => $Cpanel::authuser,
            worker_alias => $alias,
            token        => $token,
            module       => $module,
            function     => $fn,
            arguments    => $args_hr,
        );
    };
}

#----------------------------------------------------------------------

=head2 @results = call_all_workers_uapi( $MOD, $FN, \%ARGS )

Calls UAPI $MOD::$FN with %ARGS on all of the user’s child nodes.

The return is a list of hash references. Each item represents a
B<SUCCESSFUL> API call. (See below about failures.) Members are:

=over

=item * C<worker_type> - The worker type (e.g., C<Mail>) that the child node
fulfills.

=item * C<alias> - The child node’s alias.

=item * C<result> - A L<Cpanel::Result> instance that describes the result
of the remote API call.

=back

When a remote API call fails, that failure is warn()ed about, and the result
is discarded. If different behavior proves useful, that can be implemented
as needed.

=cut

sub call_all_workers_uapi ( $mod, $fn, $args_hr ) {
    Cpanel::Context::must_be_list();

    require Cpanel::LinkedNode::Worker::GetAll;
    my @workers = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser( \%Cpanel::CPDATA );

    my @results;

    for my $worker_hr (@workers) {
        my $result = call_worker_uapi(
            $worker_hr->{'worker_type'},
            $mod, $fn, $args_hr,
        );

        if ( $result->status() ) {
            push @results, {
                %{$worker_hr}{ 'worker_type', 'alias' },
                result => $result,
            };
        }
        else {
            my $remote_alias = $worker_hr->{'alias'};
            my $conf         = Cpanel::LinkedNode::User::get_node_configuration($remote_alias);
            my $hostname     = $conf->hostname();

            warn "$hostname failed $mod\::$fn: " . $result->errors_as_string();
        }
    }

    return @results;
}

#----------------------------------------------------------------------

=head2 $result_or_undef = call_worker_api2( $WORKER_TYPE, $MOD, $FN, \%ARGS )

Like C<call_worker_uapi()> but for API2, and because API2 doesn’t have
an accessor class for its response, the non-undef return here is a plain
hash reference.

=cut

sub call_worker_api2 {
    my ( $worker_type, $module, $fn, $args_hr ) = @_;

    return _call( 'call_api2', $worker_type, $module, $fn, $args_hr );
}

#----------------------------------------------------------------------

=head2 $ar_or_undef = get_alias_and_token( $WORKER_TYPE )

If the current user has a worker node of type $WORKER_TYPE configured,
this returns a 2-member array reference with:

=over

=item * the worker node’s alias

=item * the API token to use to make $WORKER_TYPE API calls on
the worker node

=back

Note that currently there is no need for the above returns except
to know whether the user has a worker node of the given type configured.
This logic is being left in place for potential future needs.

=cut

sub get_alias_and_token ($link_type) {

    # Sanity check
    if ( !%Cpanel::CPDATA ) {
        die 'cpuser data isn’t in %Cpanel::CPDATA!';
    }

    return Cpanel::LinkedNode::Worker::Storage::read( \%Cpanel::CPDATA, $link_type );
}

1;
