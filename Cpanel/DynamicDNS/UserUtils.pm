package Cpanel::DynamicDNS::UserUtils;

# cpanel - Cpanel/DynamicDNS/UserUtils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::UserUtils

=head1 SYNOPSIS

    my @domains = Cpanel::DynamicDNS::UserUtils::get_ddns_domains_for_zone( 'bobs-stuff.com' );

=head1 DESCRIPTION

This module contains logic for use in unprivileged dynamic DNS code
that isn’t of use in the actual web call logic.

=cut

#----------------------------------------------------------------------

use Cpanel::AdminBin::Call              ();
use Cpanel::WebCalls::Entry::DynamicDNS ();

use Cpanel::DynamicDNS::UtilsBackend ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @domains = get_ddns_domains_for_zone( $ZONENAME )

Returns a list of dynamic DNS subdomains that depend on $ZONENAME.

=cut

sub get_ddns_domains_for_zone ($zonename) {
    local ( $@, $! );

    my $entries_hr = Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'GET_ENTRIES',
    );

    my @entries;

    for my $entry_hr ( values %$entries_hr ) {
        next if $entry_hr->{'type'} ne 'DynamicDNS';

        Cpanel::WebCalls::Entry::DynamicDNS->adopt($entry_hr);
        push @entries, $entry_hr;
    }

    return Cpanel::DynamicDNS::UtilsBackend::get_ddns_domains(
        $Cpanel::user,
        \@entries,
        $zonename,
    );
}

*ddns_zone_error = *Cpanel::DynamicDNS::UtilsBackend::ddns_zone_error;

1;
