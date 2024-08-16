package Cpanel::IP::CpRapid;

# cpanel - Cpanel/IP/CpRapid.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::NAT                         ();
use Cpanel::DIp::MainIP                 ();
use Cpanel::Validate::Domain::Normalize ();

=encoding utf-8

=head1 NAME

Cpanel::IP::CpRapid

=head1 SYNOPSIS

    my $name = Cpanel::IP::CpRapid::ipv4_to_name('1.2.3.4');

    my $current_hostname = Cpanel::IP::CpRapid::get_hostname();

    my $is_cprapid = Cpanel::IP::CpRapid::is_subdomain_of_cprapid('1-2-3-4.cprapid.com');

=head1 DESCRIPTION

cPanel maintains a domain C<cprapid.com> whose subdomains auto-resolve
to the appropriate IP address. For example, an A query to
C<1-2-3-4.cprapid.com> resolves to 1.2.3.4.

This module provides logic for that interface in a single location.

=cut

#----------------------------------------------------------------------

use constant _AUTO_DOMAIN => '.cprapid.com';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ipv4_to_name( $IPV4_ADDRESS )

Converts

=cut

sub ipv4_to_name ($ipv4) {
    return ( $ipv4 =~ tr/./-/r ) . _AUTO_DOMAIN;
}

=head2 get_hostname()

Returns the cprapid hostname for the current server.

example: 10-2-66-80.cprapid.com

=cut

sub get_hostname() {
    my $public_ip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() );
    return Cpanel::IP::CpRapid::ipv4_to_name($public_ip);
}

=head2 is_subdomain_of_cprapid( $DOMAIN )

Returns true if the provided string represents a subdomain of cprapid.com,
otherwise returns false.

=cut

sub is_subdomain_of_cprapid ($domain) {
    return unless defined $domain;
    $domain =~ s/\.$//;
    $domain = Cpanel::Validate::Domain::Normalize::normalize( $domain, 1 );
    return $domain =~ /\Q@{[ _AUTO_DOMAIN() ]}\E\Z/xms;
}

1;
