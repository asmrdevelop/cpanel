package Cpanel::LinkedNode::Convert::Common::Mail::FromRemote;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/FromRemote.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::FromRemote

=head1 SYNOPSIS

(Not much interesting to show about this module.)

=head1 DESCRIPTION

This module contains various pieces of logic that are common
for mail conversions from a remote node.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::LinkedNode::Convert::Common::Child         ();
use Cpanel::LinkedNode::Convert::Common::Mail::Backend ();

use Cpanel::PromiseUtils ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 undo__set_up_source_manual_mx ( \%INPUT, $STATE_OBJ )

Undoes C<step__set_up_source_manual_mx()>’s work.

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

$STATE_OBJ must contain C<node_obj> (a
L<Cpanel::LinkedNode::Privileged::Configuration> instance) and
the C<old_source_manual_mx> value from C<step__set_up_source_manual_mx()>.

=cut

sub undo__set_up_source_manual_mx ( $, $state_obj ) {

    require Cpanel::Exim::ManualMX::APIRevert;

    my $p = Cpanel::Exim::ManualMX::APIRevert::undo_p(
        $state_obj->get('source_node_obj')->get_async_remote_api(),
        $state_obj->get('old_source_manual_mx'),
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

=head2 undo__set_up_source_service_proxy ( \%INPUT, $STATE_OBJ )

Undoes C<step__set_up_source_service_proxy()>’s work.

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::Common::Mail::FromRemoteStateBase>
instance.

%INPUT must contain C<username>, and $STATE_OBJ must contain C<source_node_obj>
(a L<Cpanel::LinkedNode::Privileged::Configuration> instance)
and C<old_source_service_proxy>.

=cut

sub undo__set_up_source_service_proxy ( $input_hr, $state_obj ) {

    my $api_obj = $state_obj->get('source_node_obj')->get_async_remote_api();

    my $set_params_hr = _convert_old_proxy_to_set_call_args(
        $input_hr->{'username'},
        $state_obj->get('old_source_service_proxy'),
    );

    my $unset_p = $api_obj->request_whmapi1(
        'unset_all_service_proxy_backends',
        { %{$input_hr}{'username'} },
    )->then(
        sub {
            return $set_params_hr && $api_obj->request_whmapi1(
                'set_service_proxy_backends',
                $set_params_hr,
            );
        }
    );

    Cpanel::PromiseUtils::wait_anyevent($unset_p)->get();

    return;
}

#----------------------------------------------------------------------

=head2 kick_source_connections_p ( \%INPUT, $STATE_OBJ )

This terminates all mail (i.e., POP3 or IMAP) connections
on the source child node.

IMPORTANT: This step should follow proxy setup on the child node
so that further incoming mail connections will proxy to the parent node.

It expects C<username> in %INPUT and C<source_node_obj> in
$STATE_OBJ.

=cut

sub kick_source_connections_p ( $input_hr, $state_obj ) {

    my $api_obj = $state_obj->get('source_node_obj')->get_async_remote_api();

    return $api_obj->request_whmapi1(
        'terminate_cpuser_mailbox_sessions',
        { %{$input_hr}{'username'} },
    );
}

=head2 promise(..) = unchildify_former_child_account_p( \%INPUT, $STATE_OBJ )

This removes a child-node account’s designation as being part of a
distributed account. A promise is returned that resolves when that work
is done.

%INPUT must contain C<username>, and $STATE_OBJ must contain
C<source_node_obj>.

=cut

sub unchildify_former_child_account_p ( $input_hr, $state_obj ) {
    my $api = $state_obj->get('source_node_obj')->get_async_remote_api();

    return $api->request_whmapi1(
        'PRIVATE_unset_child_workloads',
        { %{$input_hr}{'username'} },
    );
}

=head2 promise(..) = delete_source_account_archives_p( \%INPUT, $STATE_OBJ )

This removes the user’s account archives on the source node.

%INPUT must contain C<username>, and $STATE_OBJ must contain
C<source_node_obj>.

=cut

sub delete_source_account_archives_p ( $input_hr, $state_obj ) {
    return Cpanel::LinkedNode::Convert::Common::Child::delete_account_archives_p(
        $state_obj->get('source_node_obj'),
        $input_hr->{'username'},
    );
}

=head2 set_up_source_manual_mx( \%INPUT, $STATE_OBJ, $TARGET_HOSTNAME )

Sets manual MX on the source server to point to $TARGET_HOSTNAME for
the user’s domains.

%INPUT must contain C<username>, and $STATE_OBJ must contain
C<source_node_obj>.

=cut

sub set_up_source_manual_mx ( $input_hr, $state_obj, $target_hostname ) {    ## no critic qw(ManyArgs) - mis-parse
    my $domains_ar = Cpanel::LinkedNode::Convert::Common::Mail::Backend::get_mail_domains_for_step($input_hr);

    my $api_obj = $state_obj->get('source_node_obj')->get_async_remote_api();

    my %child_new_mx = (
        domain  => $domains_ar,
        mx_host => [ ($target_hostname) x @$domains_ar ],
    );

    # Now configure the child with manual MX redirects that point to the local machine.
    my $set_p = $api_obj->request_whmapi1( 'set_manual_mx_redirects', \%child_new_mx );

    my $response = Cpanel::PromiseUtils::wait_anyevent($set_p)->get();

    my $old_manual_mx = $response->get_data()->{'payload'} or die 'no “payload” in set_manual_mx_redirects response!';

    $state_obj->set( 'old_source_manual_mx', $old_manual_mx );

    return;
}

=head2 set_up_source_service_proxy( \%INPUT, $STATE_OBJ, $TARGET_HOSTNAME )

Sets the user’s Mail service proxying on the source server to point to
$TARGET_HOSTNAME.

%INPUT must contain C<username>, and $STATE_OBJ must contain
C<source_node_obj>.

=cut

sub set_up_source_service_proxy ( $input_hr, $state_obj, $target_hostname ) {    ## no critic qw(ManyArgs) - mis-parse
    my $api_obj = $state_obj->get('source_node_obj')->get_async_remote_api();

    my $get_p = $api_obj->request_whmapi1(
        'get_service_proxy_backends',
        { %{$input_hr}{'username'} },
    )->then(
        sub ($response) {

            $state_obj->set( old_source_service_proxy => $response->get_data() );

            return $api_obj->request_whmapi1(
                'set_service_proxy_backends',
                {
                    %{$input_hr}{'username'},
                    general               => $target_hostname,
                    service_group         => 'Mail',
                    service_group_backend => $target_hostname,
                },
            );
        }
    );

    Cpanel::PromiseUtils::wait_anyevent($get_p)->get();

    return;
}

#----------------------------------------------------------------------

# This may be good to move to its own function if we end up
# needing it elsewhere.
sub _convert_old_proxy_to_set_call_args ( $username, $old_proxy_ar ) {
    return undef if !@$old_proxy_ar;

    my $set_params_hr = {
        username              => $username,
        service_group         => [],
        service_group_backend => [],
    };

    for my $proxy (@$old_proxy_ar) {
        if ( !$proxy->{'service_group'} ) {
            $set_params_hr->{'general'} = $proxy->{'backend'};
        }
        else {
            push @{ $set_params_hr->{'service_group'} },         $proxy->{'service_group'};
            push @{ $set_params_hr->{'service_group_backend'} }, $proxy->{'backend'};
        }
    }

    return $set_params_hr;
}

1;
