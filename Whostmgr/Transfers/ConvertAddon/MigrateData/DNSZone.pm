package Whostmgr::Transfers::ConvertAddon::MigrateData::DNSZone;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/DNSZone.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use constant DOMAINIP_NO_CACHE => 1;

use Cpanel::Config::LoadCpConf    ();
use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::DnsUtils::Config      ();
use Cpanel::DomainIp              ();
use Cpanel::Exception             ();
use Cpanel::LoadFile              ();
use Cpanel::NAT                   ();
use Cpanel::Proxy                 ();
use Cpanel::Proxy::Tiny           ();
use Whostmgr::DNS::Email          ();
use Cpanel::Encoder::URI          ();

sub new {
    my ( $class, $opts ) = @_;

    my $domain = delete $opts->{domain};
    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['domain'] ) if !$domain;

    my $self = $class->SUPER::new($opts);
    $self->{domain}   = $domain;
    $self->{zonefile} = _get_zonefile($domain);
    return $self;
}

sub _get_zonefile {
    my ($domain) = @_;
    my $dir = Cpanel::DnsUtils::Config::find_zonedir();
    return "$dir/$domain.db";
}

sub _write_zonefile {
    my ( $self, $zonedata ) = @_;

    my $zdata = 'cpdnszone-' . Cpanel::Encoder::URI::uri_encode_str( $self->{'domain'} ) . '=' . Cpanel::Encoder::URI::uri_encode_str($zonedata) . '&';
    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SYNCZONES', 0, '', '', '', $zdata );

    return 1;
}

sub save_zonefile_for_domain {
    my ($self) = @_;

    my $domain   = $self->{domain};
    my $zonefile = $self->{zonefile};
    $self->{records} = Cpanel::LoadFile::load($zonefile);
    $self->{IPv4}    = Cpanel::DomainIp::getdomainip( $domain, DOMAINIP_NO_CACHE );

    return 1;
}

sub rollback_zonefile_for_domain {
    my ($self) = @_;
    return if !$self->{records};

    $self->_write_zonefile( $self->{records} );

    return 1;
}

sub restore_zonefile_for_domain {
    my ($self) = @_;
    return if !$self->{records};
    my $domain = $self->{domain};

    my $creator     = $ENV{'REMOTE_USER'};
    my $new_RPemail = Whostmgr::DNS::Email::getzoneRPemail($creator);
    my $new_IPv4    = Cpanel::DomainIp::getdomainip( $domain, DOMAINIP_NO_CACHE );
    my $old_IPv4    = $self->{IPv4};
    if ( Cpanel::NAT::is_nat() ) {
        if ( my $nat = Cpanel::NAT::get_public_ip($new_IPv4) ) {
            $new_IPv4 = $nat;
        }
        if ( my $nat = Cpanel::NAT::get_public_ip($old_IPv4) ) {
            $old_IPv4 = $nat;
        }
    }

    # TODO, use Cpanel::ZoneFile->new( 'text' => $zoneref->{$zone}, 'domain' => $zone );
    # like we do in bin/swapip.pl instead of manually modifing the records
    my $records = $self->{records};

    # Convert SOA record to show RP email.
    $records =~ s/\bIN\s+SOA\s+\S+\s+\K\S+(?=\.\s+)/$new_RPemail/;

    # Convert A records to use new IP.
    $records =~ s/\bIN\s+A\s+\K\Q$old_IPv4\E/$new_IPv4/g;

    $self->_write_zonefile($records);

    # Add any service (formerly proxy) Subdomains
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf_ref->{'proxysubdomains'} ) {
        my @ZONE = split( /\n/, $records );

        my $proxies_hr             = Cpanel::Proxy::Tiny::get_known_proxy_subdomains();
        my @proxy_domains_to_setup = keys %$proxies_hr;

        Cpanel::Proxy::setup_proxy_subdomains( 'user' => $self->{to_username}, 'subdomain' => \@proxy_domains_to_setup, 'zone_ref' => { $domain => \@ZONE }, 'skipreload' => 1, 'ip' => $new_IPv4, 'domain_owner' => $self->{to_username} );
    }
    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', 0, $domain );

    return 1;
}

1;
