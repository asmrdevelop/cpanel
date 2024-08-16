package Cpanel::Domain::Owner;

# cpanel - Cpanel/Domain/Owner.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Domain::Owner

=head1 SYNOPSIS

  my $user = Cpanel::Domain::Owner::get_owner_or_die('koston.org');

  my $user_or_undef = Cpanel::Domain::Owner::get_owner_or_undef('koston.org');

=cut

=head1 DESCRIPTION

L<Cpanel::AcctUtils::DomainOwner::Tiny> has logic that does a simple domain
ownership lookup, but it’s incomplete because it doesn’t account for
service subdomains like C<cpanel.>.

This module provides that logic. This module is thus a one-stop-shop for
domain ownership.

=cut

#----------------------------------------------------------------------

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Exception                    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 get_owner_or_die($domain)

Obtains the owner (username) that the domain belongs to.

This function dies if the owner (username) cannot be found.

=cut

sub get_owner_or_die {
    my ($domain) = @_;

    return get_owner_or_undef($domain) || do {
        die Cpanel::Exception::create( 'DomainDoesNotExist', [ name => $domain ] );
    };
}

=head2 get_owner_or_undef($webvhost_domain)

Same as C<get_owner_or_die()> except that if there is no owner,
undef is returned.

=cut

sub get_owner_or_undef {
    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $_[0], { 'default' => undef } ) || do {
        require Cpanel::WebVhosts;
        Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( Cpanel::WebVhosts::strip_auto_domains( $_[0] ), { 'default' => undef } );
    };
}

1;
