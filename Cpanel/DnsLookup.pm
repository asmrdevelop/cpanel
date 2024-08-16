package Cpanel::DnsLookup;

# cpanel - Cpanel/DnsLookup.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::SocketIP ();

sub DnsLookup_init { }

sub api2_name2ip {
    my %OPTS = @_;

    my $domain = $OPTS{'domain'};

    my $ip = Cpanel::SocketIP::_resolveIpAddress($domain);

    return [ { 'ip' => $ip, 'domain' => $domain, 'status' => ( $ip ? 1 : 0 ), 'statusmsg' => ( $ip ? 'Resolved' : 'Could not resolve' ) } ];
}

our %API = (
    name2ip => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
