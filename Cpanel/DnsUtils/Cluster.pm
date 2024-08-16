package Cpanel::DnsUtils::Cluster;

# cpanel - Cpanel/DnsUtils/Cluster.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Autodie ();

use constant USING_CLUSTERED_DNS_TOUCHFILE => "/var/cpanel/useclusteringdns";

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Cluster - Utility functions for clustered DNS

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Cluster;

    my $is_clustering_enabled = Cpanel::DnsUtils::Cluster::is_clustering_enabled();

=head1 DESCRIPTION

This module contains utility functions related to clustered DNS.

=head1 FUNCTIONS

=head2 $is_enabled = is_clustering_enabled()

Determines whether or not DNS clustering is enabled on the server

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Returns 1 if clustering is enabled, 0 if not.

=back

=back

=cut

sub is_clustering_enabled {
    return Cpanel::Autodie::exists(USING_CLUSTERED_DNS_TOUCHFILE) ? 1 : 0;
}

1;
