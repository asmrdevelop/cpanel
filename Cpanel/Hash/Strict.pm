package Cpanel::Hash::Strict;

# cpanel - Cpanel/Hash/Strict.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Hash::Strict

=head1 SYNOPSIS

    package MyStrictHash;

    use parent 'Cpanel::Hash::Strict';

    use constant _PROPERTIES => qw( foo bar baz );

    package main;

    my $hash_obj = MyStrictHash->new()->set(
        foo => 123,
        bar => undef,
    );

    my $foo = $hash_obj->get('foo');    # 123
    my $bar = $hash_obj->get('bar');    # undef

It fails on retrieval of unset values …

    $hash_obj->get('baz');      # bang!

… and on set/retrieval of unknown values:

    $hash_obj->get('qux');      # boom!
    $hash_obj->set('qux', 123); # thunk!

=head1 DESCRIPTION

This module implements a “strict” dictionary as a base class:

=over

=item * It accepts only a limited set of properties.

=item * It fails on retrieval of unset values.

=back

This module also subclasses L<Cpanel::Destruct::DestroyDetector>
and, as protection against misuse, ties its internals to
L<Cpanel::Hash::ForObject>.

=head1 SUBCLASS INTERFACE

Subclasses must implement a C<_PROPERTIES()> method that returns the
list of allowed properties.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Carp ();

use Cpanel::Hash::ForObject ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates I<CLASS>.

=cut

sub new ($class) {
    my $self = bless {}, $class;

    tie %$self, 'Cpanel::Hash::ForObject', $class;

    return $self;
}

=head2 $obj = I<OBJ>->set( $NAME1 => $VALUE1, $NAME2 => ... )

Sets one or more values in I<OBJ>. Values may be any scalar, including undef.

=cut

sub set ( $self, %name_values ) {
    for my $name ( keys %name_values ) {
        $self->_fail_if_name_is_unknown($name);
    }

    @{$self}{ map { "_$_" } keys %name_values } = map { \$_ } values %name_values;

    return $self;
}

=head2 $obj = I<OBJ>->get( $NAME )

Retrieves the value previous stored via C<set()>.

If no such value was ever set, a “loud” exception is thrown.
This is B<BY DESIGN> so that we catch potential cases where
the code fails to set a falsy value.

=cut

sub get ( $self, $name ) {
    my $val_sr = $self->{"_$name"} or do {
        $self->_fail_if_name_is_unknown($name);
        Carp::confess("$self: Unset property: $name");
    };

    return $$val_sr;
}

sub _fail_if_name_is_unknown ( $self, $name ) {
    if ( !grep { $name eq $_ } $self->_PROPERTIES() ) {
        Carp::confess("$self: Unknown property: $name");
    }

    return;
}

1;
