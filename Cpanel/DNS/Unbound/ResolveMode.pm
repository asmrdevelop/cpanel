package Cpanel::DNS::Unbound::ResolveMode;

# cpanel - Cpanel/DNS/Unbound/ResolveMode.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::ResolveMode

=head1 SYNOPSIS

    Cpanel::DNS::Unbound::ResolveMode::set_up( $dns_unbound_obj )

=head1 DESCRIPTION

This module implements logic to control L<DNS::Unbound>’s resolver mode.

Ordinarily we want unbound to do fully-recursive DNS resolutions—particularly
in, e.g., AutoSSL, where it’s important that we maximize confidence in a
certificate order before sending it. This optimizes the user experience
by giving good error messages. It also minimizes load on the AutoSSL
provider.

On some servers, though, fully-recursive DNS resolutions don’t work, e.g.,
because of firewall restrictions. For such cases we expose the ability
to configure unbound as a stub resolver.

This functionality is B<NOT> considered stable and should B<ONLY> be used
as a last resort. Generally speaking, it’s far better to allow recursive
DNS lookups.

=head1 HOW TO CONFIGURE

Create a symbolic link at $_PATH below whose value is either:

=over

=item * C<recursive> - (default) Do recursive lookups.

=item * C<stub> - Do stub lookups, using the resolvers listed in
F</etc/resolv.conf>.

=back

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie qw(readlink);

# accessed via tests
our $_PATH;
BEGIN { $_PATH = '/var/cpanel/dns_unbound_resolve_mode'; }

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 set_up( $DNS_UNBOUND_OBJ )

Accepts an instance of L<DNS::Unbound> and configures its resolver settings
as per the system’s configuration.

=cut

sub set_up ($dns_unbound_obj) {
    if ( my $mode = Cpanel::Autodie::readlink_if_exists($_PATH) ) {
        if ( $mode eq 'stub' ) {
            $dns_unbound_obj->resolvconf();
        }
        elsif ( $mode ne 'recursive' ) {
            die "Bad “$_PATH” value: “$mode”";
        }
    }

    return;
}

1;
