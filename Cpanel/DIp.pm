package Cpanel::DIp;

# cpanel - Cpanel/DIp.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig           ();
use Cpanel::ConfigFiles                  ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::DIp::MainIP                  ();
use Cpanel::DIp::IsDedicated             ();
use Cpanel::DIp::Owner                   ();
use Cpanel::DIp::Group                   ();
use Cpanel::IP::Configured               ();
use Cpanel::Server::Type::License        ();
use Cpanel::Debug                        ();
use Cpanel::Reseller                     ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::Config::userdata::Load       ();

our $VERSION = 1.8;

*getmainip              = *Cpanel::DIp::MainIP::getmainip;
*getmainserverip        = *Cpanel::DIp::MainIP::getmainserverip;
*getconfiguredips       = *Cpanel::IP::Configured::getconfiguredips;
*isdedicatedip          = *Cpanel::DIp::IsDedicated::isdedicatedip;
*getsharedipslist       = *Cpanel::DIp::IsDedicated::getsharedipslist;
*getipsfromfilelist     = *Cpanel::DIp::IsDedicated::getipsfromfilelist;
*clearcache             = *Cpanel::DIp::IsDedicated::clearcache;
*getunallocatedipslist  = *Cpanel::DIp::IsDedicated::getunallocatedipslist;
*get_dedicated_ip_owner = *Cpanel::DIp::Owner::get_dedicated_ip_owner;
*get_all_dedicated_ips  = *Cpanel::DIp::Owner::get_all_dedicated_ips;
*get_available_ips      = *Cpanel::DIp::Group::get_available_ips;

use constant USER_FOR_UNOWNED_DOMAINS => 'nobody';

sub getresellerhash {
    my $reseller      = shift || return;
    my $err_ref       = shift;
    my $resellershash = get_allresellerips_hash( $err_ref, $reseller );
    my $hasdelegated  = 0;

    foreach my $ip ( keys %{$resellershash} ) {
        if ( !exists $resellershash->{$ip}{'delegated'}{$reseller} ) {
            if ( !exists $resellershash->{$ip}{'shared'}{$reseller} ) {
                delete $resellershash->{$ip};
            }
        }
        else {
            $hasdelegated = 1;
        }
    }
    if ( !$hasdelegated ) {
        foreach my $ip ( Cpanel::DIp::IsDedicated::getunallocatedipslist() ) {
            $resellershash->{$ip}{'free'} = 1;
        }
    }
    return wantarray ? %{$resellershash} : $resellershash;
}

sub get_allresellerips_hash {
    my ( $errmsg_ref, $reseller ) = @_;
    my %allresellers;

    foreach my $reseller_l ( Cpanel::Reseller::getresellerslist(), 'root' ) {
        my $reseller_ips_hashref = Cpanel::DIp::Group::_get_resellersips_hash($reseller_l);
        foreach my $ip ( keys %{$reseller_ips_hashref} ) {

            $allresellers{$ip}->{'free'} = $reseller_ips_hashref->{$ip}{'free'};

            next if ( !exists $reseller_ips_hashref->{$ip}{'delegated'}
                && !exists $reseller_ips_hashref->{$ip}{'shared'} );

            foreach my $type (qw(delegated shared)) {
                foreach my $name ( $reseller_l, '_main' ) {
                    if ( defined $reseller_ips_hashref->{$ip}{$type}{$name} ) {
                        $allresellers{$ip}->{$type}{$name} = $reseller_ips_hashref->{$ip}{$type}{$name};
                    }
                }
            }
        }
    }

    for my $ip ( keys %allresellers ) {

        # fix up hash however you need
        if ( exists $allresellers{$ip}->{'delegated'} ) {
            if ( keys %{ $allresellers{$ip}->{'delegated'} } > 1 ) {
                _fix_multi_delegated_ips( $ip, \%allresellers, $errmsg_ref, $reseller || '' );
            }
        }
    }

    return wantarray ? %allresellers : \%allresellers;
}

#whichever reseller has the fewest delegated IPs, then fewest shared IPs, "wins" the IP.
sub _fix_multi_delegated_ips {
    my ( $ip, $allresellers, $errmsg_ref, $calledreseller ) = @_;
    if ( !defined $calledreseller ) { $calledreseller = q{}; }
    my $winning_reseller = q{};
    my %decision_maker;

    my $resellerlost = 0;
    for my $reseller ( keys %{ $allresellers->{$ip}{'delegated'} } ) {
        if ( $reseller eq $calledreseller ) {
            ${$errmsg_ref} .= qq{IP $ip has multiple delegations!\n};
            $resellerlost = 1;
        }
        $winning_reseller                                = $reseller if !$winning_reseller;
        $decision_maker{$reseller}->{'num_of_delegated'} = @{ Cpanel::DIp::Group::getdelegatedipslist($reseller)    || [] };
        $decision_maker{$reseller}->{'num_of_shared'}    = @{ Cpanel::DIp::IsDedicated::getsharedipslist($reseller) || [] };
        $allresellers->{$ip}{'delegated'}{$reseller}     = 0;
    }

    my ( $first_low, $second_low ) = sort { $decision_maker{$a}{'num_of_delegated'} <=> $decision_maker{$b}{'num_of_delegated'} } keys %decision_maker;

    if ( $decision_maker{$first_low}->{'num_of_delegated'} == $decision_maker{$second_low}->{'num_of_delegated'} ) {

        if ( $decision_maker{$first_low}->{'num_of_shared'} < $decision_maker{$second_low}->{'num_of_shared'} ) {
            $winning_reseller = $first_low;
        }
        elsif ( $decision_maker{$first_low}->{'num_of_shared'} > $decision_maker{$second_low}->{'num_of_shared'} ) {
            $winning_reseller = $second_low;
        }
    }
    else {
        $winning_reseller = $first_low;
    }
    if ($resellerlost) {
        if ( $calledreseller ne 'root' ) {
            ${$errmsg_ref} .= qq{IP $ip has been removed from your delegation!\n};
            ${$errmsg_ref} .= qq{Please contact the server admin with any questions.\n};
        }
        else {
            ${$errmsg_ref} .= qq{IP $ip has been removed from root's delegation!\n};
            ${$errmsg_ref} .= qq{IP was awarded to the reseller $winning_reseller.\n};
        }
    }
    elsif ( $calledreseller eq $winning_reseller ) {
        ${$errmsg_ref} .= qq{IP $ip was kept in your delegation.\n};
    }
    if ( !$calledreseller ) {
        ${$errmsg_ref} .= qq{IP $ip has multiple delegations!\n};
        ${$errmsg_ref} .= qq{IP $ip has been awarded to the reseller $winning_reseller.\n};
    }
    $allresellers->{$ip}{'delegated'}{$winning_reseller} = 1;
    return;
}

sub getreservedipreasons {
    my ($reservedipreasons) = {};

    Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::RESERVED_IP_REASONS_FILE, $reservedipreasons );

    return if !( keys %{$reservedipreasons} );

    return $reservedipreasons;
}

sub getnameserverips {
    my %nsips;

    require Cpanel::DnsUtils::NameServerIPs;
    my $ns_data = Cpanel::DnsUtils::NameServerIPs::load_nameserver_ips();
    foreach my $nameserver ( keys %{ $ns_data->{'data'} } ) {
        my $ip = $ns_data->{'data'}->{$nameserver}->{'ipv4'} or next;
        $nsips{$ip} = $nameserver;
    }

    return wantarray ? %nsips : \%nsips;
}

#ip/[resellers] ... just in case multiple resellers have been delegated a single IP
sub _get_all_delegated_ips {
    my %ip_resellers;

    my $reseller_lookup = shift() || { map { $_ => 1 } ( Cpanel::Reseller::getresellerslist(), 'root' ) };

    if ( opendir( my $dir_fh, $Cpanel::ConfigFiles::DELEGATED_IPS_DIR ) ) {

        while ( my $filename = readdir($dir_fh) ) {
            if ( $reseller_lookup->{$filename} ) {
                foreach my $ip ( Cpanel::DIp::IsDedicated::getipsfromfilelist( "$Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$filename", 1 ) ) {    #skip exists check
                    if ( defined $ip_resellers{$ip} ) {
                        push @{ $ip_resellers{$ip} }, $filename;
                    }
                    else {
                        $ip_resellers{$ip} = [$filename];
                    }
                }
            }
        }
        close $dir_fh;
    }

    return %ip_resellers;
}

*get_all_shared_ips = \&_get_all_shared_ips;

#ip/[resellers]
sub _get_all_shared_ips {
    my $reseller_lookup = shift;

    my @resellers = $reseller_lookup ? keys %{$reseller_lookup} : ( Cpanel::Reseller::getresellerslist(), 'root' );
    my %ip_resellers;

    foreach my $reseller ( sort @resellers ) {
        foreach my $ip ( Cpanel::DIp::IsDedicated::getsharedipslist($reseller) ) {
            if ( exists $ip_resellers{$ip} ) {
                push @{ $ip_resellers{$ip} }, $reseller;
            }
            else {
                $ip_resellers{$ip} = [$reseller];
            }
        }
    }

    return %ip_resellers;
}

#return all information about all IPs: delegation, designation, sharing, free
# TODO: move this to Cpanel::DIp::Info
sub get_ip_info {
    Cpanel::AcctUtils::DomainOwner::Tiny::build_domain_cache() if !$Cpanel::AcctUtils::DomainOwner::Tiny::CACHE_IS_SET;

    my $domain_to_user_map = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my $reseller_lookup    = { map { $_ => 1 } ( Cpanel::Reseller::getresellerslist(), 'root' ) };

    my %ipdata = map { $_ => undef } ( Cpanel::IP::Configured::getconfiguredips() );

    my %dedicated_ips = Cpanel::DIp::Owner::get_all_dedicated_ips();
    foreach my $ip ( keys %dedicated_ips ) {
        $ipdata{$ip}{'dedicated'}      = $dedicated_ips{$ip};
        $ipdata{$ip}{'dedicated_user'} = $domain_to_user_map->{ $dedicated_ips{$ip} } || USER_FOR_UNOWNED_DOMAINS;
    }

    my %delegated_ips = _get_all_delegated_ips($reseller_lookup);
    foreach my $ip ( keys %delegated_ips ) {
        $ipdata{$ip}{'delegated'} = $delegated_ips{$ip};
    }

    foreach my $ip ( Cpanel::DIp::Group::getreservedipslist() ) {
        $ipdata{$ip}{'reserved'} = 1;
    }

    my $reserved_ip_reasons = getreservedipreasons();
    foreach my $ip ( keys %{$reserved_ip_reasons} ) {
        $ipdata{$ip}{'reserved_reason'} = $reserved_ip_reasons->{$ip};
    }

    my %nameserverips = getnameserverips();
    foreach my $ip ( grep { $nameserverips{$_} } keys %ipdata ) {
        $ipdata{$ip}{'nameserver'} = $nameserverips{$ip};
    }

    my %shared_ips = _get_all_shared_ips($reseller_lookup);

    if ( Cpanel::Server::Type::License::is_ea4_allowed() ) {
        my $nobody_ip_hr = _get_unowned_ips_lookup();

        my $httpd_ip_hr = _get_ip_httpd_users_lookup();

        # Anything that is not a dedicated IP is by definition a shared IP
        foreach my $ip ( grep { !$ipdata{$_}{'dedicated'} } keys %ipdata ) {
            $ipdata{$ip}{'shared'} = _sorted_uniq_arrayref(

                # users from the reseller shared ips
                @{ $shared_ips{$ip} },

                ( $httpd_ip_hr->{$ip} ? keys( %{ $httpd_ip_hr->{$ip} } ) : () ),

                # see if “nobody” uses this IP address
                exists( $nobody_ip_hr->{$ip} ) ? USER_FOR_UNOWNED_DOMAINS : (),
            );
        }
    }
    return wantarray ? %ipdata : \%ipdata;
}

sub _get_ip_httpd_users_lookup {
    my %ips_lookup;

    require Cpanel::Config::userdata::Cache;
    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache();

    my %want = ( 'main' => 1, 'sub' => 1 );
    foreach my $rec ( grep { $want{ $_->[2] } } values %$userdata_cache ) {
        for my $ipv4 ( grep { $_ } @{$rec}[ 5, 6 ] ) {
            substr( $ipv4, index( $ipv4, ':' ) ) = q<>;

            $ips_lookup{$ipv4}{ $rec->[0] } = undef;
        }
    }

    return \%ips_lookup;
}

sub _get_unowned_ips_lookup {
    return {} if !Cpanel::Config::userdata::Load::user_exists(USER_FOR_UNOWNED_DOMAINS);

    require Cpanel::Config::WebVhosts;
    my @nobody_vh_ips;
    local $@;

    # CPANEL-24866: warn on failure to load WebVhosts for USER_FOR_UNOWNED_DOMAINS instead of throw
    eval {
        my $wvh = Cpanel::Config::WebVhosts->load(USER_FOR_UNOWNED_DOMAINS);

        my @vhs = ( $wvh->main_domain(), $wvh->subdomains() );

        @nobody_vh_ips = map {
            my $vh_conf = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( USER_FOR_UNOWNED_DOMAINS, $_ );

            if ( !$vh_conf || !%$vh_conf ) {
                $vh_conf = Cpanel::Config::userdata::Load::load_userdata_domain( USER_FOR_UNOWNED_DOMAINS, $_ );
            }

            if ( !$vh_conf || !%$vh_conf ) {

                # On a fresh install there will be no IPs
                # and this expected so it should not warn.
                ();
            }
            else {
                $vh_conf->{'ip'};
            }
        } @vhs;
    };
    if ( my $err = $@ ) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn($err);
    }
    my %nobody_ip;
    @nobody_ip{@nobody_vh_ips} = ();

    return \%nobody_ip;
}

sub _sorted_uniq_arrayref {
    return [ sort keys %{ { map { $_ => undef } @_ } } ];    ## no critic (ProhibitVoidMap)
}

sub reseller_can_use_all_ips {
    my ($reseller) = @_;

    if ( !Cpanel::Reseller::isreseller($reseller) ) {
        Cpanel::Debug::log_warn("'$reseller' is not a reseller, but something thinks it is!");
        return 0;
    }

    return !-f "$Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$reseller" ? 1 : 0;
}

1;
