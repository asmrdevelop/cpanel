package Cpanel::UUID;

# cpanel - Cpanel/UUID.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Rand::Get ();

=head1 NAME

Cpanel::UUID

=head1 DESCRIPTION

Functions to generate truly random (version 4) UUIDs according to RFC 4122.

=head1 FUNCTIONS

=head2 random_uuid()

Generate a random version 4 UUID and return it.  The UUID is written in the
traditional format as a hex string with dashes.

=cut

sub random_uuid {
    my $bytes = Cpanel::Rand::Get::getranddata( 16, 'binary' );

    # Setting these bits this way is required by RFC 4122.
    vec( $bytes, 35, 2 ) = 0x2;
    vec( $bytes, 13, 4 ) = 0x4;
    return join '-', unpack( 'H8 H4 H4 H4 H12', $bytes );
}

1;
