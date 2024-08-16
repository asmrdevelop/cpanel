package Cpanel::DnsUtils::cPanel;

# cpanel - Cpanel/DnsUtils/cPanel.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::PwCache                      ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::Config::WebVhosts            ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::WebVhosts::AutoDomains       ();

sub get_cpanel_generated_dns_names ( $domain = undef ) {

    my ( $user, $homedir, $abshomedir, $useproxy, $maindomain, $domain_ref );

    if ( $Cpanel::user && $Cpanel::homedir && $Cpanel::abshomedir && scalar keys %Cpanel::CPDATA ) {
        $user       = $Cpanel::user;
        $homedir    = $Cpanel::homedir;
        $abshomedir = $Cpanel::abshomedir;
        $maindomain = $Cpanel::CPDATA{'DNS'};
        $domain_ref = \@Cpanel::DOMAINS;
        $useproxy   = ( $Cpanel::CONF{'proxysubdomains'} ? 1 : 0 );
    }
    else {
        $user       = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
        $homedir    = ( Cpanel::PwCache::getpwnam($user) )[7];
        $abshomedir = $homedir;
        if ( -l $abshomedir ) {
            $abshomedir = readlink($abshomedir);
        }
        return unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        return if ( !scalar keys %{$cpuser_ref} );
        $maindomain = $cpuser_ref->{'DOMAIN'};
        $domain_ref = $cpuser_ref->{'DOMAINS'};
        push @{$domain_ref}, $maindomain;
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $useproxy = ( $cpconf->{'proxysubdomains'} ? 1 : 0 );
    }

    my %NON_CUSTOM_DOMAINS = $useproxy
      ? map {
        $_ . '.' . $maindomain . '.' => undef,
          ( length $domain ? ( $_ . '.' . $domain . '.' => undef ) : () ),
      } ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_PROXIES() )
      : ();

    my @subs = Cpanel::Config::WebVhosts->load($user)->subdomains();

    foreach my $sub ( @subs, $domain, $maindomain, @{$domain_ref} ) {
        next if ( !$sub || $sub eq '' );
        $NON_CUSTOM_DOMAINS{ $sub . '.' } = undef;
        foreach my $reserved ( Cpanel::WebVhosts::AutoDomains::RESERVED_FOR_SUBS() ) {
            $NON_CUSTOM_DOMAINS{ $reserved . '.' . $sub . '.' } = undef;
        }
    }

    foreach my $sub ( Cpanel::WebVhosts::AutoDomains::ALWAYS_RESERVED() ) {
        $NON_CUSTOM_DOMAINS{ $sub . '.' . $maindomain . '.' } = undef;
    }

    $NON_CUSTOM_DOMAINS{''} = undef;    #use a null name

    return \%NON_CUSTOM_DOMAINS;
}

1;
