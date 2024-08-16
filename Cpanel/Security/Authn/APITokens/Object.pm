package Cpanel::Security::Authn::APITokens::Object;

# cpanel - Cpanel/Security/Authn/APITokens/Object.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Object

=head1 SYNOPSIS

See end classes.

=head1 DESCRIPTION

This is a base class for API token objects. This implements interactions
with API tokens as they’re stored in the datastore.

Note that token verification is implemented not here
but in L<Cpanel::Security::Authn::APITokens>.

=head1 METHODS

The following instance methods are publicly exposed in subclasses:

=head2 I<CLASS>->new( %PARAMS )

Returns a new instance of I<CLASS>.

%PARAMS should be at least:

=over

=item * C<name> (string)

=item * C<create_time> (epoch seconds)

=item * C<expires_at> (epoch seconds)

=back

=cut

sub new {
    my ( $class, %self ) = @_;

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_name()

Returns the token’s name.

=cut

sub get_name {
    return $_[0]->{'name'};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_create_time()

Returns the token’s creation time (epoch seconds).

=cut

sub get_create_time {
    return $_[0]->{'create_time'};
}

=head2 I<OBJ>->get_expires_at()

Returns the token’s creation time (epoch seconds).

=cut

sub get_expires_at {
    return $_[0]->{'expires_at'};
}

=head2 I<OBJ>->get_whitelist_ips()

Returns the whitelisted IP addresses or CIDR IP address ranges. If the list is undefined or empty, all IP addresses
are allowed.

=cut

sub get_whitelist_ips {
    return $_[0]->{'whitelist_ips'};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->export()

Returns a hash reference that contains the object’s data.
Subclasses document the specifics of this format individually.

=cut

sub export {
    return $_[0]->_export();
}

# Allow for subclasses to override.
sub _export {
    return { %{ $_[0] } };
}

# Just in case something doesn’t call export():
*TO_JSON = *export;

1;
