package Cpanel::IP::NonlocalBind;

# cpanel - Cpanel/IP/NonlocalBind.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::IP::NonlocalBind - Check to see if ipv4 ip_nonlocal_bind is enabled

=head1 SYNOPSIS

    use Cpanel::IP::NonlocalBind;

    my $enabled = Cpanel::IP::NonlocalBind::ipv4_ip_nonlocal_bind_is_enabled();

=head2 ipv4_ip_nonlocal_bind_is_enabled

A thin wrapper to fetch the sysctl value of 'net.ipv4.ip_nonlocal_bind'

=cut

sub ipv4_ip_nonlocal_bind_is_enabled {
    require Cpanel::Sysctl;

    local $@;
    my $ip_nonlocal_bind_contents = eval { Cpanel::Sysctl::get('net.ipv4.ip_nonlocal_bind') };
    warn if $@;

    return $ip_nonlocal_bind_contents;
}
1;
