
# cpanel - Cpanel/DnsUtils/UsercPanel.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DnsUtils::UsercPanel;

use cPstrict;

use Cpanel::DomainLookup           ();
use Cpanel::WebVhosts::AutoDomains ();

sub get_cpanel_generated_dns_names ( $domain = undef ) {    # as a user

    my ( $user, $homedir, $abshomedir, $useproxy, $maindomain, $domain_ref );

    $user       = $Cpanel::user;
    $homedir    = $Cpanel::homedir;
    $abshomedir = $Cpanel::abshomedir;
    $maindomain = $Cpanel::CPDATA{'DNS'};
    $domain_ref = \@Cpanel::DOMAINS;
    $useproxy   = ( $Cpanel::CONF{'proxysubdomains'} ? 1 : 0 );

    my %NON_CUSTOM_DOMAINS = $useproxy
      ? map {
        $_ . '.' . $maindomain . '.' => undef,
          ( length $domain ? ( $_ . '.' . $domain . '.' => undef ) : () ),
      } ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_PROXIES() )
      : ();

    my @subs = keys { Cpanel::DomainLookup::listsubdomains() }->%*;

    foreach my $sub ( @subs, $domain, $maindomain, @{$domain_ref} ) {
        next if ( !$sub || $sub eq '' );
        $sub =~ s/_/\./g;
        $NON_CUSTOM_DOMAINS{ $sub . '.' } = undef;
        foreach my $reserved ( Cpanel::WebVhosts::AutoDomains::RESERVED_FOR_SUBS() ) {
            $NON_CUSTOM_DOMAINS{ $reserved . '.' . $sub . '.' } = undef;
        }
    }

    foreach my $sub ( Cpanel::WebVhosts::AutoDomains::ALWAYS_RESERVED() ) {
        $NON_CUSTOM_DOMAINS{ $sub . '.' . $maindomain . '.' } = undef;
    }

    return \%NON_CUSTOM_DOMAINS;
}

1;
