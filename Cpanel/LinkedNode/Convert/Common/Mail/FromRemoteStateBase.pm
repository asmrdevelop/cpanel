package Cpanel::LinkedNode::Convert::Common::Mail::FromRemoteStateBase;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/FromRemoteStateBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::RemoteStateBase

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This base class implements logic shared by remote-sourced conversions
(e.g., from-distributed and cross-distributed).

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::LinkedNode::Convert::Common::Mail::StateBase';

use Cpanel::IP::Convert ();

use constant _PROPERTIES => (
    __PACKAGE__->SUPER::_PROPERTIES(),

    'source_node_hostname',
    'source_node_ips',
    'source_node_obj',
    'source_backup_dir',

    'target_cpmove_path',

    'old_source_manual_mx',
    'old_source_service_proxy',
);

#----------------------------------------------------------------------

=head1 PROTECTED METHODS

=head2 $yn = I<OBJ>_Source_server_claims_ip( $IP_ADDR )

Implements C<_source_server_claims_ip()> for from-remote conversions,
but subclasses need to call this explicitly.

=cut

sub _Source_server_claims_ip ( $self, $ip_addr ) {

    my $normalized_ip    = Cpanel::IP::Convert::normalize_human_readable_ip($ip_addr);
    my $check_against_ar = $self->get('source_node_ips');

    return !!grep { $normalized_ip eq Cpanel::IP::Convert::normalize_human_readable_ip($_) } @{$check_against_ar};
}

=head2 $yn = I<OBJ>_Source_server_claims_domain_p( $NAME )

Implements C<_source_server_claims_domain_p()> for from-remote conversions,
but subclasses need to call this explicitly.

=cut

sub _Source_server_claims_domain_p ( $self, $name ) {
    my $async_api = $self->get('source_node_obj')->get_async_remote_api();

    return $async_api->request_whmapi1( 'getdomainowner', { domain => $name } )->then(
        sub ($getdomainowner_resp) {
            return !!$getdomainowner_resp->get_data()->{user};
        }
    );
}

#----------------------------------------------------------------------

sub _origin_hostname ($self) {
    return $self->get('source_node_hostname');
}

1;
