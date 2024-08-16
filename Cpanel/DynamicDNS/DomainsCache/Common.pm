package Cpanel::DynamicDNS::DomainsCache::Common;

# cpanel - Cpanel/DynamicDNS/DomainsCache/Common.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::DomainsCache::Common

=head1 DESCRIPTION

Common logic for the dynamic DNS domain cache modules.

=cut

#----------------------------------------------------------------------

use Cpanel::DatastoreDir::Init ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $path = get_path()

Returns the cache’s filesystem path.

=cut

sub get_path () {
    my $dsdir = Cpanel::DatastoreDir::Init::initialize();
    return "$dsdir/dynamicdns-domain-id-cache";
}

=head2 $str_sr = serialize(\%DOMAIN_ID)

Returns a reference to a string of the %DOMAIN_ID data.

=cut

sub serialize ($domain_id_hr) {
    return \join(
        "\n",
        q<>,
        ( map { "$_:$domain_id_hr->{$_}" } keys %$domain_id_hr ),
        q<>,
    );
}

1;
