package Cpanel::API::Chkservd;

# cpanel - Cpanel/API/Chkservd.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exim::Ports ();

sub get_exim_ports {
    my ( $args, $result ) = @_;
    $result->data( { 'ports' => [ Cpanel::Exim::Ports::get_insecure_ports() ] } );
    return 1;
}

sub get_exim_ports_ssl {
    my ( $args, $result ) = @_;
    $result->data( { 'ports' => [ Cpanel::Exim::Ports::get_secure_ports() ] } );
    return 1;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    _worker_node_type  => 'Mail',
    get_exim_ports     => $allow_demo,
    get_exim_ports_ssl => $allow_demo,
);

1;
