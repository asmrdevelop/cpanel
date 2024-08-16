package Cpanel::DnsAdmin::Query::GETZONES;

# cpanel - Cpanel/DnsAdmin/Query/GETZONES.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsAdmin::Query::GETZONES

=head1 DESCRIPTION

This module implements handler logic for C<GETZONES> dnsadmin queries.
It extends L<Cpanel::DnsAdmin::Query>.

=head1 RESPONSE FORMAT

This parses the dnsadmin response to a hashref of
C<{ $zonename =E<gt> $zonetext, … }>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::DnsAdmin::Query';

use Cpanel::Encoder::URI ();

#----------------------------------------------------------------------

sub _parse_response ( $, $text ) {
    return {
        map {
            # CPANEL-20449
            # We must ignore empty zones
            # so that Cpanel::Domain::Zone does not provide
            # the wrong zone. We don’t have control over whether
            # dnsadmin provides it to us (e.g., it could be
            # errantly auto-vivified within a custom dnsadmin
            # module), so we have to filter them out here.
            #
            # Note also that a TXT record that ends with “=” would
            # be URI-encoded at this point still, so we can safely
            # just check on final “=”.
            #
            # Also note, it was possible in v84 for servers to send cpdnskeys
            # in this context. This is no longer a problem with v86, but we
            # still need to filter them here as we could have v84 servers
            # in a dns cluster.

            substr( $_, -1 ) ne '=' && rindex( $_, 'cpdnskey', 0 ) != 0 ? (
                ( substr( $_, 0, index( $_, '=' ) ) =~ s/^cpdnszone-//r ) => (
                    Cpanel::Encoder::URI::uri_decode_str( substr( $_, index( $_, '=' ) + 1 ) ) // ''    #
                )
              )
              : ()
          }
          split( m/&/, $text )
    };
}

1;
