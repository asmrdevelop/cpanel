package Cpanel::DIp::Owner;

# cpanel - Cpanel/DIp/Owner.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig           ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ConfigFiles                  ();

=encoding utf-8

=head1 NAME

Cpanel::DIp::Owner - Functions to determine dedicated ip ownership

=head1 SYNOPSIS

    use Cpanel::DIp::Owner ();

    my $owner = Cpanel::DIp::Owner::get_dedicated_ip_owner('4.4.4.4');

    my $all_dedicated_ips = Cpanel::DIp::Owner::get_all_dedicated_ips();

=cut

=head2 get_dedicated_ip_owner($ip)

Returns the user that owns a dedicated ip.  If the ip is not
dedicated or unowned this returns ''

=cut

sub get_dedicated_ip_owner {
    my ($ip) = @_;
    my $dedicated_ips_ref = get_all_dedicated_ips();
    return q{} if !$dedicated_ips_ref->{$ip};
    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $dedicated_ips_ref->{$ip}, { 'default' => '' } );
}

=head2 get_all_dedicated_ips()

Returns as hashref of ip => domain for all dedicated
ips on the system.

=cut

sub get_all_dedicated_ips {

    # If this file doesn't exist, we haven't created it yet, since we haven't
    # set up any dedicated IPs.

    # ip => domain map
    if ( my $ipdomains_ref = Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::DEDICATED_IPS_FILE, undef, ': ' ) ) {
        return wantarray ? %$ipdomains_ref : $ipdomains_ref;
    }

    return wantarray ? () : {};
}

1;
