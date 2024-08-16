package Cpanel::Market::Provider::Utils;

# cpanel - Cpanel/Market/Provider/Utils.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Market::Provider::Utils - Utilities for cPanel Market provider modules

=head1 SYNOPSIS

    use Cpanel::Market::Provider::Utils ();

    my $docroot = Cpanel::Market::Provider::Utils::get_docroot_for_domain('harry.com');

    Cpanel::Market::Provider::Utils::install_dns_entries_of_type(
        [
            [ '_test1.example.com' => 'Value #1' ],
            [ '_test1.www.example.com' => 'Value #2' ],
        ],
        'TXT',
    );

    Cpanel::Market::Provider::Utils::remove_dns_names_of_type(
        [
            '_test1.example.com',
            '_test1.www.example.com',
        ],
        'TXT',
    );

=head1 DESCRIPTION

This module is provided for use within Market provider modules. cPanel offers
it as an API that 3rd-party SSL providers can treat as reliable across
versions of cPanel & WHM.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::WebVhosts ();

=head2 get_docroot_for_domain( DOMAIN )

See documentation in C<Cpanel::WebVhosts>.

=cut

#NOTE: This module very likely will consist solely of functionality that’s
#just aliased from other modules. This is by design, as this module is
#documented for 3rd-party providers, while those modules are not.

*get_docroot_for_domain = *Cpanel::WebVhosts::get_docroot_for_domain;

#----------------------------------------------------------------------

=head2 install_dns_entries_of_type( \@ENTRIES, $TYPE )

@ENTRIES is an array reference of 2-member array references; each
2-member array reference is [ $name => $value ]. For each entry,
this function will update the appropriate DNS zone so that a query against
that name and the $TYPE (e.g., C<TXT> or C<CNAME>) will return at least
the given value.

This takes account of authoritative subdomains to prevent record occlusion.

See the SYNOPSIS for an example.

=cut

sub install_dns_entries_of_type {
    my ( $entries_ar, $type ) = @_;

    require Cpanel::DnsUtils::Batch;
    return Cpanel::DnsUtils::Batch::set_for_type( $type, $entries_ar );
}

=head2 remove_dns_names_of_type( \@NAMES, $TYPE )

@NAMES is an array reference of names to remove. For each name,
all DNS resource records that match that name are removed.

See the SYNOPSIS for an example.

=cut

sub remove_dns_names_of_type {
    my ( $names_ar, $type ) = @_;

    require Cpanel::DnsUtils::Batch;
    return Cpanel::DnsUtils::Batch::unset_for_type( $type, $names_ar );
}

1;
