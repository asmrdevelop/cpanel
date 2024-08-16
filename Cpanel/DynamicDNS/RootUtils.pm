package Cpanel::DynamicDNS::RootUtils;

# cpanel - Cpanel/DynamicDNS/RootUtils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::RootUtils

=head1 SYNOPSIS

    my @domains = Cpanel::DynamicDNS::RootUtils::get_ddns_domains_for_zone( 'bob', 'bobs-stuff.com' );

=head1 DESCRIPTION

This module contains logic for use in privileged dynamic DNS code
that isn’t of use in the actual web call logic.

=cut

#----------------------------------------------------------------------

use Cpanel::WebCalls::Datastore::Read ();
use Cpanel::DynamicDNS::UtilsBackend  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @domains = get_ddns_domains_for_zone( $USERNAME, $ZONENAME )

Returns a list of dynamic DNS subdomains that depend on $ZONENAME,
which belongs to $USERNAME.

=cut

sub get_ddns_domains_for_zone ( $username, $zonename ) {
    local ( $@, $! );

    my $entries_hr = Cpanel::WebCalls::Datastore::Read->read_for_user($username);

    my @entries = grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS') } values %$entries_hr;

    return Cpanel::DynamicDNS::UtilsBackend::get_ddns_domains(
        $username,
        \@entries,
        $zonename,
    );
}

*ddns_zone_error = *Cpanel::DynamicDNS::UtilsBackend::ddns_zone_error;

1;
