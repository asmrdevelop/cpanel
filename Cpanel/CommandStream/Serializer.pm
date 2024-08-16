package Cpanel::CommandStream::Serializer;

# cpanel - Cpanel/CommandStream/Serializer.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Serializer - Base class for CommandStream serializers

=head1 SYNOPSIS

    my $ser = Cpanel::CommandStream::Serializer::MyFormat->new();

    my $str = $ser->stringify( { what => 'ever' } );

    my $thing = $ser->parse(\$str);

=head1 SUBCLASS INTERFACE

A subclass B<MUST> provide:

=over

=item * C<_serialize($thing)> - Implements C<stringify()>.

=item * C<_deserialize(\$byte_str)> - Implements C<parse()>.

=back

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {}, $class;
}

=head2 $byte_str = I<OBJ>->stringify( $THING )

Returns a byte string that serializes C<$THING>.

=cut

sub stringify ( $self, $str ) {
    return $self->_serialize($str);
}

=head2 $thing = I<OBJ>->parse( \$BYTE_STR )

The reverse of C<stringify()>, but its input is a
I<reference> to the string.

=cut

sub parse ( $self, $str ) {
    return $self->_deserialize($str);
}

1;
