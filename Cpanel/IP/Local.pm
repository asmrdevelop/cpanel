package Cpanel::IP::Local;

# cpanel - Cpanel/IP/Local.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::NAT ();

=encoding utf-8

=head1 NAME

Cpanel::IP::Local - Obtain a list of public IP addresses pointing to this server

=head1 SYNOPSIS

    use Cpanel::IP::Local ();

    my @ipv4_and_ipv6_public_ips = Cpanel::IP::Local::get_local_systems_public_ips();

    my @ipv6_ips = Cpanel::IP::Local::get_local_systems_public_ipv6_ips();

=cut

=head2 get_local_systems_public_ips()

Returns a list of ipv4 ipv6 addresses that are bound to this computer.

If the system uses 1:1 nat the addresses are the public addresses.

=cut

#XXX: This function can fail in many ways that we currently do not report.
#TODO: Retool the called logic to report errors, ideally via exceptions.
sub get_local_systems_public_ips {
    require Cpanel::Linux::RtNetlink;
    require Cpanel::Context;
    require Cpanel::Ips::Fetch;

    Cpanel::Context::must_be_list();

    return (
        ( map { Cpanel::NAT::get_public_ip($_) } Cpanel::Ips::Fetch::fetch_ips_array() ),
        get_local_systems_public_ipv6_ips()
    );
}

=head2 get_local_systems_public_ipv6_ips()

Returns a list of ipv6 addresses that are bound to this computer.

=cut

sub get_local_systems_public_ipv6_ips {
    require Cpanel::Linux::RtNetlink;
    my $ipv6_ref = Cpanel::Linux::RtNetlink::get_addresses_by_interface('AF_INET6');    # Warning: not cached!

    my @ips;
    foreach my $device ( keys %{$ipv6_ref} ) {
        my $device_addresses = $ipv6_ref->{$device};
        foreach my $address ( keys %{$device_addresses} ) {
            push @ips, $device_addresses->{$address}{'ip'};
        }
    }
    return @ips;
}

1;
