package Cpanel::Domain::ExternalResolver;

# cpanel - Cpanel/Domain/ExternalResolver.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::IP::LocalCheck      ();
use Cpanel::PromiseUtils        ();
use Cpanel::DNS::Unbound::Async ();

=encoding utf-8

=head1 NAME

Cpanel::Domain::ExternalResolver - Wrapper around Cpanel::DNS::Unbound::Async

=head1 DESCRIPTION

Perform common DNS queries using external DNS instead of using the resolvers configured
in /etc/resolv.conf. The two main reasons for wanting to do this are concern that the
configured resolvers may 1) have a cache that is out of date, or 2) return records that
exist locally but are not available to the internet in general.

For a generic lookup facility that bypasses the locally configured resolvers, see
C<Cpanel::DNS::Unbound::Async>.

=head1 SYNOPSIS

    use Cpanel::Domain::ExternalResolver ();

    if ( Cpanel::Domain::ExternalResolver::domain_is_on_local_server($hostname) ) {
        # we can use it
    }

    # - or -

    if ( Cpanel::Domain::ExternalResolver::domain_resolves($hostname) ) {
        # we can use it
    }

=head1 FUNCTIONS

=head2 $yn = domain_resolves( $DOMAIN )

Check whether the domain has any A records.

Returns a boolean:

=over

=item * 0, if $DOMAIN lacks A records

=item * 1, if $DOMAIN has >= 1 A record

=back

This throws an exception if the query fails for any reason other than
C<NXDOMAIN>.

=cut

sub domain_resolves ($domain) {
    my $result = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::DNS::Unbound::Async->new()->ask( $domain, 'A' ),
    )->get();

    return @{ $result->decoded_data() } && 1;
}

=head2 $yn = domain_is_on_local_server( $DOMAIN )

This function works like Cpanel::Domain::Local except that it checks external DNS
instead of the server's configured DNS (/etc/resolv.conf)

Returns a boolean:

=over

=item * 0, if $DOMAIN lacks A records

=item * 0, if any of $DOMAIN’s A records contains a nonlocal IP

=item * 1, if $DOMAIN has >= 1 A record, and all of those contain local IPs

=back

This throws an exception if the query fails for any reason other than
C<NXDOMAIN>.

=cut

sub domain_is_on_local_server ($domain) {
    my $result = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::DNS::Unbound::Async->new()->ask( $domain, 'A' ),
    )->get();

    for my $ip ( @{ $result->decoded_data() } ) {
        return 0 if !Cpanel::IP::LocalCheck::ip_is_on_local_server($ip);
    }

    return @{ $result->decoded_data() } && 1;
}

1;
