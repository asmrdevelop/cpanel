package Cpanel::DnsUtils::Sync;

# cpanel - Cpanel/DnsUtils/Sync.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains ();
use Cpanel::DnsUtils::AskDnsAdmin   ();
use Cpanel::DnsUtils::Constants     ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::Debug                   ();

our $verbose = 0;

our $DOMAINS_PER_BATCH = Cpanel::DnsUtils::Constants::SYNCZONES_BATCH_SIZE();

sub _sync_zone {
    my $domain    = shift;
    my $localflag = shift || 0;
    $domain =~ s/\.\.//g;
    $domain =~ s/\///g;
    if ( my $zonedata = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONES', 0, $domain, 0, 0, { keys => 1 } ) ) {
        my $response = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SYNCZONES', $localflag, '', '', '', $zonedata );    #SAFETY CHECK OK
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', $localflag, $domain );                               # SYNCZONES doesn't require output, so this can't be skipped in case of error?
        return $response;
    }
    else {
        return ( undef, "Domain “$domain” could not be found.\n" );
    }
}

sub sync_zone_local {
    my $domain = shift;
    _sync_zone( $domain, 1 );
}

sub sync_zone {
    my $domain = shift;
    _sync_zone( $domain, 0 );
}

sub _sync_zones {
    my $localflag         = shift || 0;
    my $user_domains_only = shift || 0;
    my $print             = shift;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{'dnsadmin_verbose_sync'} ) {
        $verbose = 1;
    }

    my $sync_count = 0;
    my $userdomains_ref;
    if ($user_domains_only) { $userdomains_ref = Cpanel::Config::LoadUserDomains::loaduserdomains( {}, 1 ); }
    my @DOMAINS = split( "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin('GETZONELIST') );
    if ($user_domains_only) {
        @DOMAINS = grep { exists $userdomains_ref->{$_} } @DOMAINS;
    }
    my $domain_count = scalar @DOMAINS;

    while (@DOMAINS) {

        # If the domain is not on the server and we have user_domains_only sync (!full)
        # Then do not sync it in.
        my @DOMAINQUEUE = splice( @DOMAINS, 0, $DOMAINS_PER_BATCH );

        if ($verbose) {
            Cpanel::Debug::log_info( __PACKAGE__ . "::_sync_zones: Syncing " . join( ',', @DOMAINQUEUE ) );
        }

        if ($print) {
            print " [${sync_count}/${domain_count}] \n";
        }

        if ( my $zonedata = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONES', 0, join( ',', @DOMAINQUEUE ), 0, 0, { keys => 1 } ) ) {
            Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SYNCZONES', $localflag, '', '', '', $zonedata );
        }

        $sync_count += scalar @DOMAINQUEUE;
    }
    if ($print) {
        print " [${sync_count}/${domain_count}] \n";
    }

    # After everything is done we do a full reload
    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADBIND', 0 );
    if ($verbose) {
        Cpanel::Debug::log_info( __PACKAGE__ . "::_sync_zones: " . $sync_count . " zones synced." );
    }
    return $sync_count;
}

sub sync_zones {
    my $user_domains_only = shift;
    my $print             = shift;
    return _sync_zones( 0, $user_domains_only, $print );
}

sub sync_zones_local {
    my $user_domains_only = shift;
    my $print             = shift;
    return _sync_zones( 1, $user_domains_only, $print );
}

1;
