
# cpanel - Cpanel/ImagePrep/Check/server_linkages.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::server_linkages;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';

use Cpanel::DNSLib::PeerConfig      ();
use Cpanel::LinkedNode::Index::Read ();
use Whostmgr::ClusterServer         ();

=head1 NAME

Cpanel::ImagePrep::Check::server_linkages - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<EOF;
Check whether any of the following are set up:
  - Linked Server Nodes
  - DNS Cluster
  - Configuration Cluster

All of these are unsuitable for template VMs.
EOF
}

sub _check ($self) {
    $self->_check_type( 'Linked Server Node',    sub { sort keys %{ Cpanel::LinkedNode::Index::Read::get() } } );
    $self->_check_type( 'DNS Cluster',           sub { Cpanel::DNSLib::PeerConfig::getdnspeerlist( [qw(write-only sync standalone)] ) } );
    $self->_check_type( 'Configuration Cluster', sub { sort keys %{ Whostmgr::ClusterServer->new()->get_list_scramble_keys() } } );
    return;
}

sub _check_type ( $self, $type, $get_items ) {
    my @items = $get_items->();
    if (@items) {
        die <<EOF;
You have one or more $type servers configured. This is not a supported configuration for template VMs.

$type servers:
@{[join "\n", map { "  - $_" } @items]}
EOF
    }

    $self->loginfo("No $type was found");
    return;
}

1;
