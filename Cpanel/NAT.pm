package Cpanel::NAT;

# cpanel - Cpanel/NAT.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::NAT::Object ();

my $nat;

sub set_cpnat {
    $nat = shift;
    return;
}

sub cpnat {
    return $nat ||= Cpanel::NAT::Object->new();
}

sub reload {
    return cpnat()->load_file();
}

# $_[0] = $local_ip
sub get_public_ip {
    return ( $nat ||= cpnat() )->get_public_ip( $_[0] );
}

# $_[0] = $public_ip
sub get_local_ip {
    return ( $nat ||= cpnat() )->get_local_ip( $_[0] );
}

# $_[0] = $local_ip
sub get_public_ip_raw {
    return ( $nat ||= cpnat() )->get_public_ip_raw( $_[0] );
}

sub ordered_list {
    return cpnat()->ordered_list();
}

sub get_all_public_ips {
    return cpnat()->get_all_public_ips();
}

sub is_nat {
    return cpnat()->enabled();
}

1;
