package Whostmgr::API::1::Nameserver;

# cpanel - Whostmgr/API/1/Nameserver.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SocketIP        ();
use Whostmgr::Nameserver    ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    get_nameserver_config => undef,
    lookupnsip            => undef,
    lookupnsips           => undef,
    resolvedomainname     => undef,
    set_nameserver        => undef,
};

sub lookupnsip {
    my ( $args, $metadata ) = @_;
    my $host = $args->{'host'};
    my $ip   = Whostmgr::Nameserver::get_ip_from_nameserver($host);
    if ( !defined $ip ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to determine IP address from nameserver.';
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'ip' => $ip };
}

sub lookupnsips {
    my ( $args, $metadata ) = @_;
    my $host = $args->{'host'};
    my $ips  = Whostmgr::Nameserver::get_ips_for_nameserver($host);
    if ( ref $ips ne 'HASH' || !( $ips->{'ipv4'} || $ips->{'ipv6'} ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to determine IP address from nameserver.';
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return $ips;
}

sub resolvedomainname {
    my ( $args, $metadata ) = @_;
    my $domain = $args->{'domain'};
    my $ip     = Cpanel::SocketIP::_resolveIpAddress($domain);
    if ( !$ip ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to resolve domain name.';
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'ip' => $ip };
}

sub get_nameserver_config {
    my ( $args, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'nameservers' => [ Whostmgr::Nameserver::get_nameserver_config() ] };
}

sub set_nameserver {
    my ( $args, $metadata ) = @_;

    my $ns = lc( $args->{nameserver} );
    if ( !$ns || $ns !~ /^(bind|powerdns|disabled)$/ ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Bind, powerdns, and disabled are valid nameserver options.';
        return;
    }

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['ServerTasks'], "setupnameserver $ns" );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { nameserver => $ns, 'message' => "Queued task to set nameserver to $ns successfully." };
}

1;
