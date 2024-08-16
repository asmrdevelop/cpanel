package Cpanel::Hash;

# cpanel - Cpanel/Hash.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use strict;

=encoding utf-8

=head1 NAME

Cpanel::Hash

=head1 FUNCTIONS

This module creates a NON-cryptographic hash that is suitable for lookups

=cut

=head1 SYNOPSIS

    use Cpanel::Hash ();

    my $hash = Cpanel::Hash::get_fastest_hash('data');

=cut

=head1 DESCRIPTION

=head2 get_fastest_hash( SCALAR )

=head3 Purpose

Provide a non-cryptographic hash suitable for hash table and checksum use.
(The actual hashing algorithm is undefined!)

=head3 Arguments

=over

=item SCALAR - The data used to generate the hash

=back

=head3 Returns

=over

=item An integer containing a reproducible hash

=back

=cut

*get_fastest_hash = \&fnv1a_32;

=head2 fnv1a_32( SCALAR )

=head3 Purpose

Generate a hash using 32-bit FNV-1a. This has the same
input/output as C<get_fastest_hash()>; they’re actually currently the
same function, but for applications where you’re storing values for
retrieval later, you should call this function directly since
C<get_fastest_hash()> doesn’t guarantee that it will always return the
same hash value for the same input (i.e., the algorithm that it uses is
subject to change).

=cut

#http://www.isthe.com/chongo/src/fnv/fnv.h
use constant FNV1_32A_INIT => 0x811c9dc5;

#http://www.isthe.com/chongo/src/fnv/hash_32a.c
use constant FNV_32_PRIME => 0x01000193;

use constant FNV_32_MOD => 2**32;    # AKA 0x100000000 but that it non-portable;
#
# A pure Perl implementation of Fowler–Noll–Vo v1a 32-bit.
# cf. http://www.isthe.com/chongo/src/fnv/hash_32a.c
#
sub fnv1a_32 {
    my $fnv32 = FNV1_32A_INIT();
    ( $fnv32 = ( ( $fnv32 ^ $_ ) * FNV_32_PRIME() ) % FNV_32_MOD ) for unpack( 'C*', $_[0] );
    return $fnv32;
}

1;
