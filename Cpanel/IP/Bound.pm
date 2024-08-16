package Cpanel::IP::Bound;

# cpanel - Cpanel/IP/Bound.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Socket::Constants       ();
use Cpanel::Validate::IP::v4        ();
use Cpanel::IP::NonlocalBind::Cache ();
use Cpanel::SV                      ();

=encoding utf-8

=head1 NAME

Cpanel::IP::Bound - Lightweight tools to see if an IP address is bound to the system

=head1 SYNOPSIS

    use Cpanel::IP::Bound;

    Cpanel::IP::Bound::ipv4_is_bound('192.0.2.8') # 0
    Cpanel::IP::Bound::ipv4_is_bound($mainip) # 1

=head2 ipv4_is_bound($ip_addr)

Returns 1 if the IP Address is bound on the system

Returns 0 if the IP Address is not bound on this sytem.

Note that multicast addresses (224.0.0.0 - 239.255.255.255) are invalid
per this interface.

=cut

# “man 2 bind” says this only happens with a local/UNIX socket,
# but in testing it happens reliably with IPv4 as well.
use constant {
    _EADDRNOTAVAIL => 99,
    _EADDRINUSE    => 98
};

sub ipv4_is_bound {
    my ($addr) = @_;
    my $fd;

    return 0 unless Cpanel::Validate::IP::v4::is_valid_ipv4($addr);

    if ( index( $addr, '.' ) == 3 ) {
        if ( ( substr( $addr, 0, 3 ) >= 224 ) && ( substr( $addr, 0, 3 ) < 240 ) ) {
            warn "Multicast address ($addr) cannot be tested via this interface!\n";
            return 0;
        }
    }

    my $ipv4_ip_nonlocal_bind_is_enabled = Cpanel::IP::NonlocalBind::Cache::ipv4_ip_nonlocal_bind_is_enabled();
    if ( !defined $ipv4_ip_nonlocal_bind_is_enabled || $ipv4_ip_nonlocal_bind_is_enabled ) {
        return _slow_ipv4_is_bound_via_configured_ips($addr);
    }

    local $!;
    socket( $fd, $Cpanel::Socket::Constants::PF_INET, $Cpanel::Socket::Constants::SOCK_STREAM, $Cpanel::Socket::Constants::IPPROTO_TCP ) or die "socket(PF_INET, SOCK_STREAM, IPPROTO_TCP): $!";

    # case CPANEL-21915: whmredirect will have $addr marked as tainted
    # since we validate above this is OK to untaint
    Cpanel::SV::untaint($addr);

    bind( $fd, pack( 'SnC4x8', $Cpanel::Socket::Constants::AF_INET, 0, split( m{\.}, $addr ) ) ) or do {

        # EADDRINUSE can happen if there are no more ephemeral ports
        # to assign. To see this in action do:
        #
        #   sysctl net.ipv4.ip_local_port_range="60998 60999"
        #
        return 1 if $! == _EADDRINUSE();

        warn "bind($addr): $!\n" if $! != _EADDRNOTAVAIL();

        return 0;
    };

    return 1;
}

sub _slow_ipv4_is_bound_via_configured_ips {
    my ($addr) = @_;
    require Cpanel::IP::Configured;
    my $configured_ips_ar = Cpanel::IP::Configured::getconfiguredips();
    foreach my $check_ip (@$configured_ips_ar) {
        return 1 if $check_ip eq $addr;
    }
    return 0;

}

1;
