package Cpanel::IO::SelectHelper;

# cpanel - Cpanel/IO/SelectHelper.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::IO::SelectHelper

=head1 SYNOPSIS

    my $help = Cpanel::IO::SelectHelper->new()->add(
        my_in1    => $fh1,
        my_out1   => $fh2,
        my_socket => $fh3,
        #...
    );

    my $rin = $help->get_bitmask( 'my_in1', 'my_socket', ... );
    my $win = $help->get_bitmask( 'my_out1', 'my_socket', ... );

    $help->get_fh('my_in1');    #returns $fh1

    #This leaves only 'my_in1' in the bitmask.
    $help->remove_from_bitmask( \$rin, 'my_socket' );

    $help->matches_bitmask( 'my_out1', $rin );  #false
    $help->matches_bitmask( 'my_in1', $rin );   #true

=head1 DESCRIPTION

C<select()> is fundamentally difficult to work with. This is partly because
a given filehandle has three different representations:

=over

=item 1) The bit vector (i.e., mask) that represents the descriptor (a string).
This is what C<select()> uses.

=item 2) The file descriptor (a number). This is what most system calls use.

=item 3) Perl’s file handle. This is what Perl built-ins use.

=back

This module tries to ease the pain of juggling all of this
by adding a bit of syntactic sugar to work with filehandle bit masks as
nicknames. It won’t make your code much smaller, but it’ll at least make
it easier to read—particularly if you’re new to C<select()>.

=cut

use Cpanel::FHUtils::Tiny ();

=head1 METHODS

=head2 I<CLASS>->new( NAME1 => FH_OR_MASK1, NAME2 => FH_OR_MASK2, ... )

Instantiates this class. The arguments are given as
nickname/filehandle-or-mask pairs; i.e., “FH_OR_MASK*” can be either a
filehandle or a bitmask.

=cut

sub new {
    my ( $class, @adds ) = @_;

    return bless( {}, $class )->add(@adds);
}

=head2 I<OBJ>->add( NAME1 => FH_OR_MASK1, NAME2 => FH_OR_MASK2, ... )

Add one or more filehandles to an instance. Returns OBJ.

=cut

sub add {
    my ( $self, @name_fh ) = @_;

    #sanity check
    die "odd number of args!" if @name_fh % 2;

    while ( my ( $name, $fh ) = splice( @name_fh, 0, 2 ) ) {
        if ( ref $fh ) {
            $fh = Cpanel::FHUtils::Tiny::to_bitmask($fh);
        }
        $self->{'_bitmask'}{$name} = $fh;
    }

    return $self;
}

=head2 I<OBJ>->get_bitmask( NAME1, NAME2, ... )

Returns a single bitmask for the given named filehandles.

=cut

sub get_bitmask {
    my ( $self, @names ) = @_;

    my $mask = q<>;
    $mask |= $self->{'_bitmask'}{$_} for @names;

    return $mask;
}

=head2 I<OBJ>->remove_from_bitmask( MASK_REF, NAME1, NAME2, ... )

Removes the given named filehandles from the referred-to bitmask
and returns the OBJ. This is useful, e.g., if you know that an input
filehandle no longer has anything to say, so you want to remove that
filehandle from the input bitmask that you give to C<select()>.

(NB: MASK_REF is a scalar reference.)

=cut

sub remove_from_bitmask {
    my ( $self, $mask_ref, @names ) = @_;

    if ( 'SCALAR' ne ref $mask_ref ) {
        die "mask must be a SCALAR ref, not “$mask_ref”";
    }

    my $copy = $$mask_ref;

    for my $name (@names) {
        my $name_mask = $self->{'_bitmask'}{$name};
        if ( ( $$mask_ref & $name_mask ) =~ tr<\0><>c ) {
            $copy ^= $name_mask;
        }
        else {
            die "can’t remove “$name” from bitmask that lacks it!";
        }
    }

    $$mask_ref = $copy;

    return $self;
}

=head2 I<OBJ>->matches_bitmask( NAME, BITMASK )

Returns a boolean that indicates whether the BITMASK matches
the named filehandle.

=cut

sub matches_bitmask {
    my ( $self, $name, $mask ) = @_;

    return ( ( $mask & $self->{'_bitmask'}{$name} ) eq $self->{'_bitmask'}{$name} );
}

1;
