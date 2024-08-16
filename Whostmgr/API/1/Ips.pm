package Whostmgr::API::1::Ips;

# cpanel - Whostmgr/API/1/Ips.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Ips::Shared      ();
use Whostmgr::Ips              ();
use Whostmgr::ACLS             ();
use Whostmgr::API::1::Utils    ();
use Cpanel::IP::Local          ();
use Cpanel::IPv6::RFC5952      ();
use Cpanel::NAT                ();
use Cpanel::AcctUtils::Account ();

use constant NEEDS_ROLE => {
    addips        => undef,
    delip         => undef,
    get_public_ip => undef,
    get_shared_ip => undef,
    listips       => undef,
    listipv6s     => undef,
};

sub listips {
    my ( $args, $metadata ) = @_;
    my $ipref = Whostmgr::Ips::get_detailed_ip_cfg();
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    foreach my $iphash ( @{$ipref} ) {
        $iphash->{'public_ip'} = Cpanel::NAT::get_public_ip( $iphash->{'ip'} );
    }

    return { 'ip' => $ipref };
}

sub listipv6s {
    my ( $args, $metadata ) = @_;

    my @ips = map { { 'ip' => Cpanel::IPv6::RFC5952::convert($_) } } Cpanel::IP::Local::get_local_systems_public_ipv6_ips();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'ip' => \@ips };
}

sub addips {
    my ( $args, $metadata ) = @_;

    my $ips     = $args->{'ips'};
    my $netmask = $args->{'netmask'};

    my $excludes = $args->{'excludes'} || '';
    $excludes = [ split ',', $excludes ];

    my ( $status, $statusmsg, $msgref, $errmsg ) = Whostmgr::Ips::addip( $ips, $netmask, $excludes );

    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    if ( $msgref && scalar @$msgref ) {
        chomp @$msgref;
        $metadata->{'output'}->{'messages'} = $msgref;
    }
    if ( $errmsg && scalar @$errmsg ) {
        chomp @$errmsg;
        $metadata->{'output'}->{'warnings'} = $errmsg;
    }
    return;
}

sub delip {
    my ( $args, $metadata ) = @_;
    my $ip               = $args->{'ip'};
    my $ethernetdev      = $args->{'ethernetdev'};
    my $skip_if_shutdown = $args->{'skipifshutdown'};
    my ( $status, $statusmsg, $warnref ) = Whostmgr::Ips::delip( $ip, $ethernetdev, $skip_if_shutdown );

    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    if ( ref $warnref && scalar @$warnref ) {
        chomp @$warnref;
        $metadata->{'output'}->{'warnings'} = join "\n", @$warnref;
    }
    return;
}

sub get_shared_ip {
    my ( $args, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $user = Whostmgr::ACLS::hasroot() ? $args->{'user'} : undef;
    $user ||= $ENV{'REMOTE_USER'};

    Cpanel::AcctUtils::Account::accountexists_or_die($user);

    return { 'ip' => Whostmgr::Ips::Shared::get_shared_ip_address_for_creator($user) };
}

sub get_public_ip {
    my ( $args, $metadata ) = @_;
    my $ip = $args->{'ip'};
    unless ($ip) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'You must provide an IP address.';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'ok';

    return { 'public_ip' => Cpanel::NAT::get_public_ip($ip) };
}

1;
