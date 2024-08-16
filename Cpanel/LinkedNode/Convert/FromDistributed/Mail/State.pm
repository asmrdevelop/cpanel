package Cpanel::LinkedNode::Convert::FromDistributed::Mail::State;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail/State.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail::State

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This class implements L<Cpanel::Hash::Strict> to store state values
for mail-dedistribution conversions.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::LinkedNode::Convert::Common::Mail::FromRemoteStateBase';

use Promise::XS ();

use constant _PROPERTIES => (
    __PACKAGE__->SUPER::_PROPERTIES(),

    'always_matches_ip_addr',
    'defer_dns',
    'deferred',
    'original_node_alias',
    'original_node_token',
    'tempdir',
);

use constant {
    _SOURCE_IPS_KEY      => 'child_node_ips',
    _ORIGIN_HOSTNAME_KEY => 'child_node_hostname',
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $ret = I<OBJ>->request_whmapi1_or_die( .. )

A convenience wrapper around L<Cpanel::RemoteAPI::WHM>’s method of the
same name.

=cut

sub request_whmapi1_or_die ( $self, @args ) {
    my $api = $self->get('source_node_obj')->get_remote_api();

    return $api->request_whmapi1_or_die(@args);
}

#----------------------------------------------------------------------

sub _source_server_claims_ip ( $self, $ip_addr ) {

    # In a force-dedistribution we have no way to confirm what the
    # source server controls, so assume everything is controlled.
    #
    return 1 if $self->get('always_matches_ip_addr');

    return $self->_Source_server_claims_ip($ip_addr);
}

sub _source_server_claims_domain_p ( $self, $name ) {
    return Promise::XS::resolved(1) if $self->get('always_matches_ip_addr');

    return $self->_Source_server_claims_domain_p($name);
}

1;
