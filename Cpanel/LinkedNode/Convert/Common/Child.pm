package Cpanel::LinkedNode::Convert::Common::Child;

# cpanel - Cpanel/LinkedNode/Convert/Common/Child.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Child

=head1 SYNOPSIS

    my $hn_ips_ar_p = Cpanel::LinkedNode::Convert::Common::Child::get_network_setup_p($node_obj)->then(
        sub ($result_ar) {
            my ($remote_hostname, $remote_ips_ar) = @$result_ar;

            # ...
        },
    );

=head1 DESCRIPTION

This module holds logic that is useful for all linked-node conversion modules
to interact with a child node.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($data_hr_or_undef) = get_user_listaccts_p( $NODE_OBJ, $USERNAME )

Returns a promise that resolves to $USERNAME’s hash entry in a
C<listaccts> WHM API v1 call to the node that $NODE_OBJ represents.
If the user doesn’t exist on that node, the promise resolves to undef.

=cut

sub get_user_listaccts_p ( $node_obj, $username ) {
    my $search = '^' . quotemeta($username) . '$';

    my $api = $node_obj->get_async_remote_api();

    return $api->request_whmapi1(
        'listaccts',
        {
            searchtype => 'user',
            search     => $search,
        },
    )->then( sub { shift()->get_data() } );
}

=head2 promise() = delete_account_archives_p( $NODE_OBJ, $USERNAME )

Deletes all of $USERNAME’s account archives on the child node that $NODE_OBJ
represents.

=cut

sub delete_account_archives_p ( $node_obj, $username ) {
    my $api = $node_obj->get_async_remote_api();

    return $api->request_whmapi1(
        'delete_account_archives',
        {
            user => $username,
        },
    );
}

=head2 promise([$hostname, $ips_ar]) = get_network_setup_p( $NODE_OBJ )

$NODE_OBJ is a L<Cpanel::LinkedNode::Privileged::Configuration> instance.

Returns a promise that resolves to an arrayref of:

=over

=item * the remote node’s self-reported hostname

=item * the remote node’s public IP addresses (arrayref,
both IPv4 & IPv6 combined, order unspecified)

=back

IPv6 addresses will be formatted as per RFC 5952.

=cut

sub get_network_setup_p ($node_obj) {
    my $api = $node_obj->get_async_remote_api();

    my ( $hostname, @ip_addrs );

    my $hostname_p = $api->request_whmapi1('gethostname')->then(
        sub ($response) {
            $hostname = $response->get_data()->{'hostname'};
        }
    );

    my $ips_p = $api->request_whmapi1('listips')->then(
        sub ($response) {
            push @ip_addrs, $_->{public_ip} for @{ $response->get_data() };
        }
    );

    my $ipv6s_p = $api->request_whmapi1('listipv6s')->then(
        sub ($response) {
            push @ip_addrs, $_->{ip} for @{ $response->get_data() };
        }
    );

    return Promise::XS::all( $hostname_p, $ips_p, $ipv6s_p )->then(
        sub { [ $hostname, \@ip_addrs ] },
    );
}

1;
