package Cpanel::LinkedNode::RemoteAPI;

# cpanel - Cpanel/LinkedNode/RemoteAPI.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::RemoteAPI

=head1 SYNOPSIS

    my $api_obj = create_whmapi1('mymailworker');

    my $result = $api_obj->request_whmapi1('createacct', \%args);

=head1 DESCRIPTION

This is convenience logic for instantiating L<Cpanel::RemoteAPI::WHM>
for specific linked nodes.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $api_obj = create_whmapi1( $ALIAS )

Creates a L<Cpanel::RemoteAPI::WHM> instance for the linked node with the
given $ALIAS. The object will be set up correctly so that you can get
right to work making API calls.

=cut

sub create_whmapi1 ($alias) {
    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( alias => $alias );

    return $node_obj->get_remote_api();
}

1;
