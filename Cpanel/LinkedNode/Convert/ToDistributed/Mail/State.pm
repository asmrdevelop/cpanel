package Cpanel::LinkedNode::Convert::ToDistributed::Mail::State;

# cpanel - Cpanel/LinkedNode/Convert/ToDistributed/Mail/State.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ToDistributed::Mail::State

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This class implements L<Cpanel::LinkedNode::Convert::Common::Mail::StateBase>
to store state values for mail-distribution conversions.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::LinkedNode::Convert::Common::Mail::StateBase';

use Promise::XS ();

use Cpanel::Domain::Owner  ();
use Cpanel::Hostname       ();
use Cpanel::IP::LocalCheck ();

use constant _PROPERTIES => (
    __PACKAGE__->SUPER::_PROPERTIES(),

    'target_node_obj',
    'local_cpmove_path',
    'target_cpmove_path',
    'tar_backup_transform',
    'target_listaccts_hr',
    'delete_local',
    'work_dir_name',
    'target_user_api_token',
    'old_local_manual_mx',
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $ret = I<OBJ>->request_whmapi1_or_die( .. )

A convenience wrapper around L<Cpanel::RemoteAPI::WHM>’s method of the
same name.

=cut

sub request_whmapi1_or_die ( $self, @args ) {
    my $api = $self->get('target_node_obj')->get_remote_api();

    return $api->request_whmapi1_or_die(@args);
}

#----------------------------------------------------------------------

sub _source_server_claims_ip ( $self, $ipaddr ) {
    return Cpanel::IP::LocalCheck::ip_is_on_local_server($ipaddr);
}

*_origin_hostname = *Cpanel::Hostname::gethostname;

sub _source_server_claims_domain_p ( $self, $name ) {
    return Promise::XS::resolved( Cpanel::Domain::Owner::get_owner_or_undef($name) );
}

1;
