package Cpanel::DnsAdmin::Query;

# cpanel - Cpanel/DnsAdmin/Query.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsAdmin::Query

=head1 SYNOPSIS

    my $struct = $QUERY_CLASS->parse_response( $raw_payload );

=head1 DESCRIPTION

This base class implements a common public interface for dnsadmin query
modules.

=head1 SUBCLASS INTERFACE

Each subclass B<MUST> implement:

=over

=item * C<_parse_response($, $text)>

=back

Additionally, each subclass B<MUST> define its parse output format
(i.e., the format that C<_parse_response()> returns).

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 ? = I<CLASS>->parse_response( $RAW_PAYLOAD )

Parses the raw payload from a dnsadmin request’s response.

=cut

sub parse_response ( $class, $text ) {
    return $class->_parse_response($text);
}

1;
