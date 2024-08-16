package Cpanel::RDAP::URL;

# cpanel - Cpanel/RDAP/URL.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RDAP::URL

=head1 SYNOPSIS

    my $url = Cpanel::RDAP::URL::get_domain_url('example.com');

=head1 DESCRIPTION

This module gives URL information for L<RDAP|https://about.rdap.org>.

=cut

#----------------------------------------------------------------------

use Cpanel::HTTP::QueryString ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $url = get_for_domain( $DOMAIN )

Returns a URL that can be loaded to fetch RDAP information for the
domain $DOMAIN.

=cut

sub get_for_domain ($name) {
    my $query = Cpanel::HTTP::QueryString::make_query_string(
        {
            type   => 'domain',
            object => $name,
        }
    );

    return "https://client.rdap.org/?$query";
}
1;
