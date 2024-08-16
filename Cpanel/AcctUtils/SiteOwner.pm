package Cpanel::AcctUtils::SiteOwner;

# cpanel - Cpanel/AcctUtils/SiteOwner.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::BAMP ();
use Cpanel::AcctUtils::Owner             ();

=encoding utf-8

=head1 NAME

Cpanel::AcctUtils:::SiteOwner

=head1 SYNOPSIS

    use Cpanel::AcctUtils::SiteOwner ();
    my ( $user, $owner, $test_host ) = Cpanel::AcctUtils::SiteOwner::get_site_owner( $ENV{'HTTP_HOST'} || $ENV{'SERVER_NAME'} );
    ...

=head1 DESCRIPTION

Module for getting "who owns this website". Mostly used in CGIs like defaultwebpage or in things like Cpanel::Redirect,
as we need to know this sort of information in those scripts/modules.

=head1 METHODS

=head2 get_site_owner(HOST)

For the given HOST, return a list:

=over

=item * the username of the domain’s controlling owner

=item * the reseller who owns that user

=item * The passed-in HOST with C<www.> prefix and trailing colon-port
stripped. This should map to vhost config files
(i.e., F</var/cpanel/userdata/*>).

=back

=cut

sub get_site_owner {
    my ($test_host) = @_;

    # Strip off www. if included, as the base domain would be what we care about RE ownership
    $test_host = substr( $test_host, 4 ) if index( $test_host, 'www.' ) == 0;

    # We only want the domain name, so any trailing '/' char should be removed.
    chop($test_host) if index( $test_host, "/" ) + 1 eq length $test_host;

    #HTTP allows a port to be given with the Host header.
    #We need to strip that off if it exists.
    $test_host =~ s<:\d*><>i if index( $test_host, ":" ) != -1;

    my $user = Cpanel::AcctUtils::DomainOwner::BAMP::getdomainownerBAMP( $test_host, { 'default' => 'nobody', 'skiptruelookup' => 1 } );

    # getowner() should always return “root” if nothing else, but we provide
    # a “backup” default just in case.
    my $owner = ( $user ne 'nobody' ) && Cpanel::AcctUtils::Owner::getowner($user) || 'root';

    return ( $user, $owner, $test_host );
}

1;
