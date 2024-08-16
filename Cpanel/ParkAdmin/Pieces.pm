package Cpanel::ParkAdmin::Pieces;

# cpanel - Cpanel/ParkAdmin/Pieces.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ParkAdmin::Pieces

=head1 DESCRIPTION

This module houses pieces of individually-tested logic for
L<Cpanel::ParkAdmin>.

If anything here is of use to you beyond
that module’s context, please move it to a different namespace!

=cut

#----------------------------------------------------------------------

use Cpanel::Context           ();
use Cpanel::Config::WebVhosts ();
use Cpanel::DnsUtils::Name    ();
use Cpanel::UserZones::User   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @subdomains = get_subdomains_whose_zone_is_domain( $USERNAME, $DOMAIN )

Returns a list of $USERNAME’s subdomains whose DNS zone is $DOMAIN,
based on $USERNAME’s web vhost configuration.

=cut

sub get_subdomains_whose_zone_is_domain {
    my ( $username, $domain ) = @_;

    Cpanel::Context::must_be_list();

    my @subdomains_whose_zone_is_domain;

    my @zones = Cpanel::UserZones::User::list_user_dns_zone_names($username);

    my $wvh = Cpanel::Config::WebVhosts->load($username);

    for my $subdomain ( $wvh->subdomains() ) {
        my $zone = Cpanel::DnsUtils::Name::get_longest_short_match(
            $subdomain,
            \@zones,
        );

        if ( $zone eq $domain ) {
            push @subdomains_whose_zone_is_domain, $subdomain;
        }
    }

    return @subdomains_whose_zone_is_domain;
}

1;
