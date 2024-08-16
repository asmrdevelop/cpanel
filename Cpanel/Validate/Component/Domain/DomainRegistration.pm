package Cpanel::Validate::Component::Domain::DomainRegistration;

# cpanel - Cpanel/Validate/Component/Domain/DomainRegistration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Config::LoadCpConf  ();
use Cpanel::DIp::MainIP         ();
use Cpanel::LoadModule          ();
use Cpanel::DnsUtils::UpdateIps ();
use Cpanel::Exception           ();
use Cpanel::NAT                 ();

use Cpanel::Config::IPs::RemoteDNS  ();
use Cpanel::Config::IPs::RemoteMail ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    $self->add_optional_arguments(qw( allowunregistereddomains allowremotedomains ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    if ( !defined $self->{'allowunregistereddomains'} || !defined $self->{'allowremotedomains'} ) {
        my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $self->{'allowunregistereddomains'} = $cpanel_config_ref->{'allowunregistereddomains'} ? 1 : 0;
        $self->{'allowremotedomains'}       = $cpanel_config_ref->{'allowremotedomains'}       ? 1 : 0;
    }

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $allow_unregistered, $allow_remote ) = @{$self}{ $self->get_validation_arguments() };

    return if $allow_unregistered && $allow_remote;

    my $main_ips = _get_main_ips();
    Cpanel::LoadModule::load_perl_module('Cpanel::DnsRoots');
    my @DNSROOTS = 'Cpanel::DnsRoots'->can('fetchnameservers')->($domain);

    my @nameserver_ips;
    if (@DNSROOTS) {

        #This can actually be an array of undefs, was preventing the unreg warning from firing in many situations
        @nameserver_ips = grep { defined $_ } @{ $DNSROOTS[1] };
    }

    #Consider SOAs as well, this (broken) legacy behavior has been extant so long it's now a bug-feature
    if ( !@nameserver_ips ) {
        my @DNSROOTS_SOA = 'Cpanel::DnsRoots'->can('fetchnameservers')->( $domain, 1 );
        if (@DNSROOTS_SOA) {
            push( @nameserver_ips, grep { defined $_ } @{ $DNSROOTS_SOA[1] } );
        }
    }

    require Whostmgr::API::1::ServicesCluster;
    my %cpsc_ips;
    if ( my $cpsc = Whostmgr::API::1::ServicesCluster::get_cpsc_obj_if_possible() ) {

        # frontend if we have one and then include all workers for good measure
        #   (i.e. do not limit to "cpsc-service-dns" w/ args, do not do multi via args
        #   since those are not used in DNS and in the spirit of $main_ips (i.e. not $all_ips))
        @cpsc_ips{ $cpsc->get_frontend_ips(), $cpsc->get_worker_ips() } = ();
    }

    if ( !$allow_unregistered && !@nameserver_ips ) {
        die Cpanel::Exception::create( 'DomainNotRegistered', "Could not determine the nameserver IP addresses for “[_1]”. Please make sure that the domain is registered with a valid domain registrar.", [$domain] );
    }

    if ( !$allow_remote && @nameserver_ips ) {
        my $isonserver = 0;
        foreach my $ns_ip (@nameserver_ips) {
            next if !$ns_ip;
            if ( $main_ips->{$ns_ip} ) {
                $isonserver = 1;
                last;
            }
            elsif ( exists $cpsc_ips{$ns_ip} ) {
                $isonserver = 1;    # poor var name, really means “associated with this server” per the error below
                last;
            }
        }
        if ( !$isonserver ) {
            die Cpanel::Exception::create(
                'DomainHasUnknownNameservers',
                'This domain points to an [asis,IP] address that does not use the [asis,DNS] servers associated with this server. Transfer the domain to this server’s nameservers at the domain’s registrar or update your system to recognize the current [asis,DNS] servers. To do this, use [asis,WHM]’s Configure Remote Service IPs interface.'
            );
        }
    }

    return;
}

sub _ip_address_list_files {
    return qw{ /etc/ips /etc/ips.dnsmaster };
}

# Only place this is used
sub _get_main_ips {
    my %main_ips = ( Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() ) => 1 );
    Cpanel::DnsUtils::UpdateIps::updatemasterips();

    foreach my $iplist ( _ip_address_list_files() ) {
        next if !-e $iplist;
        if ( open my $iplist_fh, '<', $iplist ) {
            while ( my $ip_line = readline $iplist_fh ) {
                chomp $ip_line;
                my $ip = ( split( /:/, $ip_line ) )[0];
                next if !defined $ip || $ip eq '';
                $main_ips{ Cpanel::NAT::get_public_ip($ip) } = 1;
            }
            close $iplist_fh;
        }
    }

    $main_ips{ Cpanel::NAT::get_public_ip($_) } = 1
      for (
        @{ Cpanel::Config::IPs::RemoteDNS->read() },
        @{ Cpanel::Config::IPs::RemoteMail->read() },
      );

    return \%main_ips;
}

1;
