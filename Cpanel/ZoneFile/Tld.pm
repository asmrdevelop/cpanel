package Cpanel::ZoneFile::Tld;

# cpanel - Cpanel/ZoneFile/Tld.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::PublicSuffix ();

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Versioning

=head1 SYNOPSIS

    my $zone = Cpanel::ZoneFile::Tld::guess_root_domain( $domain_or_subdomain );

    Cpanel::ZoneFile::Tld::guess_root_domain( "mydomain.com" ) eq "mydomain.com";
    Cpanel::ZoneFile::Tld::guess_root_domain( "sub.mydomain.com" ) eq "mydomain.com";

    Cpanel::ZoneFile::Tld::guess_root_domain( "domain.co.uk" ) eq "domain.co.uk";
    Cpanel::ZoneFile::Tld::guess_root_domain( "sub.domain.co.uk" ) eq "domain.co.uk";

=head1 DESCRIPTION

Helpers to detect the main zonefile for a domain or a subdomain.

=cut

#----------------------------------------------------------------------

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 guess_root_domain( $domain )

Returns the zonefile name to use for a domain.

=cut

sub guess_root_domain ($domain) {
    return unless length $domain;

    $domain = lc $domain;

    my @reply = Cpanel::PublicSuffix->get_io_socket_ssl_publicsuffix_handle()->public_suffix( $domain, 1 );

    return $reply[-1];
}

1;
