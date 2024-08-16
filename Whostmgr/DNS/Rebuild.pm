package Whostmgr::DNS::Rebuild;

# cpanel - Whostmgr/DNS/Rebuild.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use 5.014;    # for s///r
use strict;
use warnings;

use Cpanel::Debug                        ();
use Cpanel::NameserverCfg                ();
use Cpanel::DomainIp                     ();
use Cpanel::NameServer::Utils            ();
use Cpanel::Validate::IP                 ();
use Cpanel::DnsUtils::AskDnsAdmin        ();
use Cpanel::ZoneFile                     ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::AcctUtils::Owner             ();
use Whostmgr::DNS::Email                 ();
use Whostmgr::DNS::MX                    ();
use Cpanel::Config::LoadWwwAcctConf      ();
use Cpanel::DnsUtils::Template           ();
use Cpanel::DIp::IsDedicated             ();
use Cpanel::DIp::MainIP                  ();
use Cpanel::Config::WebVhosts            ();
use Cpanel::Proxy                        ();
use Cpanel::NAT                          ();
use Cpanel::IPv6::User                   ();
use Cpanel::WebVhosts::AutoDomains       ();
use Cpanel::Server::Type::Role::Webmail  ();
use Cpanel::Server::Type::Role::WebDisk  ();

sub restore_dns_zone_to_defaults {
    my %OPTS   = @_;
    my $domain = $OPTS{domain} or return ( 0, 'Domain is required.' );
    my $user   = $OPTS{user} || Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain)
      or return ( 0, 'User is required.' );

    my $zone_is_system_owned = grep { $user eq $_ } qw( root system nobody );

    my $ip;

    if ($zone_is_system_owned) {
        require Cpanel::DIp::MainIP;
        $ip = Cpanel::DIp::MainIP::getmainip();
    }
    else {
        $ip = Cpanel::DomainIp::getdomainip($domain);
    }

    return ( 0, "Unable to determine the IP address for $domain" ) if !$ip;

    return ( 0, "Invalid IP ($ip) address for $domain" )
      if not Cpanel::Validate::IP::is_valid_ip($ip);

    my ( $has_ipv6, $ipv6 );

    if ( !$zone_is_system_owned ) {
        ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::User::get_user_ipv6_address($user);
    }

    my $ftpip   = $ip;
    my $creator = Cpanel::AcctUtils::Owner::getowner($user) || 'root';
    my $rpemail = Whostmgr::DNS::Email::getzoneRPemail($creator);
    my ( $nameserver, $nameserver2, $nameserver3, $nameserver4 ) = Cpanel::NameserverCfg::fetch($creator);
    my $wwwacctconf_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    # Never reset the TXT records
    my $sr = 0;
    my @txt_records;
    my $oldzone_txt = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $domain );
    if ( !$oldzone_txt ) {
        Cpanel::Debug::log_info("Failed to fetch existing zone data during rebuild of DNS zone for domain $domain");
    }
    else {
        # CPANEL-38380: If the SOA record is invalid, the call to getserialnum will die.
        # There is no reliable way to get the serial number in this instance, so we log the error
        # and send the sr to the template as 0 so that it uses today's date.
        # We should not throw an exception here since 'resetzone' calls this and it can be used
        # to resolve issues with a broken zone file.
        # NOTE: There is a chance that the serial number gets decremented with this change, but it really
        #       is best effort here since the SOA record has invalid syntax
        eval { $sr = Cpanel::NameServer::Utils::getserialnum( $oldzone_txt, 1 ); };
        Cpanel::Debug::log_info("Failed to fetch the serial number for $domain:  $@") unless $sr;

        #FIXME: This will break if the zone file uses newlines for separating
        #parts of a TXT record, e.g.:
        #
        #domain.tld. IN TXT ( "foo"
        #                     "bar" )
        #
        @txt_records = grep { !/^;/ } grep { /\s+TXT\s+/ } split /\n/, $oldzone_txt;
    }

    my ( $ttl, $nsttl ) = Cpanel::NameserverCfg::fetch_ttl_conf($wwwacctconf_ref);

    my $template = 'standard';
    if ( not Cpanel::DIp::IsDedicated::isdedicatedip($ip) ) {
        $template = 'standardvirtualftp';
        my $shared_ip_address = $wwwacctconf_ref->{ADDR};

        if ( $shared_ip_address !~ /^\d+\.\d+\.\d+\.\d+$/ ) {
            $shared_ip_address = Cpanel::DIp::MainIP::getmainip();
        }

        return ( 0, "Unable to determine main ip\n" ) if not $shared_ip_address;
        $ftpip = $shared_ip_address;
    }

    my $public_ip = Cpanel::NAT::get_public_ip($ip);
    my ( $nameddata, $zone_template_error_message ) = Cpanel::DnsUtils::Template::getzonetemplate(
        $template, $domain,
        {
            domain      => $domain,
            ip          => $public_ip,
            ftpip       => Cpanel::NAT::get_public_ip($ftpip),
            rpemail     => $rpemail,
            nameserver  => $nameserver,
            nameserver2 => $nameserver2,
            nameserver3 => $nameserver3,
            nameserver4 => $nameserver4,
            serial      => $sr,
            ttl         => $ttl,
            nsttl       => $nsttl,
            ipv6        => $has_ipv6 ? $ipv6 : undef,
        },
    );
    chomp $nameddata;

    my @subdomains;

    if ( !$zone_is_system_owned ) {
        my $wvh = Cpanel::Config::WebVhosts->load($user);
        @subdomains = grep { m<\.\Q$domain\E\z> } $wvh->subdomains();
    }

    my $zf = Cpanel::ZoneFile->new(
        text => [
            split( /\n/, $nameddata ),
            _subdomain_address_entries( $domain, $ttl, $public_ip, ( $has_ipv6 ? $ipv6 : undef ), @subdomains ),
            @txt_records,
        ],
        domain => $domain,
    );
    return ( 0, $zf->{error} ? $zf->{error} : 'Failed to parse new zone data.' )
      if not defined $zf or $zf->{error};

    $zf->comment_out_cname_conflicts();

    my $zonedata_ref = $zf->serialize();
    if ( $zonedata_ref and ref $zonedata_ref ) {
        my $zret   = '';
        my %MXDATA = Whostmgr::DNS::MX::fetchmx( "$domain.db", { $domain => $zonedata_ref } );

        #
        # We do not ask checkmx to update service (formerly proxy) subdomains because
        # we need to do it for all of them below
        #
        my $checkmx = Whostmgr::DNS::MX::checkmx(
            $domain, $MXDATA{entries}, undef,
            $Whostmgr::DNS::MX::DO_UPDATEUSERDOMAINS,
            $Whostmgr::DNS::MX::NO_UPDATE_PROXY_SUBDOMAINS,
        );
        my $zonedata = join "\n", @{$zonedata_ref};

        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

        #newaccounts could be on even if the main service (formerly proxy) subs setting
        #is off, e.g., if both were on but then the admin disabled
        # service (formerly proxy) subdomains.
        if ( !$zone_is_system_owned && $cpconf->{'proxysubdomains'} ) {
            my @subdomains = (
                Cpanel::WebVhosts::AutoDomains::PROXIES_FOR_EVERYONE(),
                ( Cpanel::Server::Type::Role::Webmail->is_enabled() ? 'webmail' : () ),
                ( Cpanel::Server::Type::Role::WebDisk->is_enabled() ? 'webdisk' : () ),
                qw(cpcalendars cpcontacts whm),
            );

            if ( $checkmx->{isprimary} && $cpconf->{autodiscover_proxy_subdomains} ) {
                push @subdomains, qw(autoconfig autodiscover);
            }

            for ( $domain, _subdomains_for_domain( $domain, @subdomains ) ) {
                my ( $status, $msg ) = Cpanel::Proxy::setup_proxy_subdomains(
                    domain     => $_,
                    subdomain  => \@subdomains,
                    zone_ref   => { $domain => $zonedata_ref },
                    skipreload => 0,
                    ip         => $public_ip,
                    has_ipv6   => $has_ipv6,
                    ipv6       => $ipv6,
                );
                return ( $status, $msg ) if $status == 0;
            }
        }
        else {
            $zret .= join '',
              map { Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( @{$_} ) } (
                [ SAVEZONE   => 0, $domain, $zonedata ],
                [ RELOADBIND => 0, $domain ],
              );
        }
        return ( 1, $zret, $zonedata, $checkmx );
    }

    return ( 0, "Error from zone parser: " . $zf->{error} );
}

# tested directly
sub _subdomain_address_entries {
    my ( $domain, $ttl, $public_ip, $ipv6, @subdomains ) = @_;
    my @zone;

    for my $basesub ( map { s/\.${domain}$//gr } _subdomains_for_domain( $domain, @subdomains ) ) {

        my @names = ($basesub);

        if ( $basesub ne '*' ) {
            push @names, map { "$_.$basesub" } Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS();
        }

        my @entry = map { join "\t", $_, $ttl, 'IN' } @names;

        push @zone, map { join "\t", $_, 'A', $public_ip } @entry;

        if ($ipv6) {
            push @zone, map { join "\t", $_, 'AAAA', $ipv6 } @entry;
        }
    }
    return @zone;
}

sub _subdomains_for_domain {
    my $domain = shift;
    return grep { /\.${domain}$/ } map { s/_/./gr } @_;
}

1;
