package Cpanel::Hash::JSONable;

# cpanel - Cpanel/Hash/JSONable.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Hash::JSONable

=head1 SYNOPSIS

    package MyHashyThing;

    use parent 'Cpanel::Hash::JSONable';

    package main;

    my $obj = _get_myhashything_instance();

    my $json = JSON::XS->convert_blessesd()->new()->encode($obj);

=head1 DESCRIPTION

This class simplifies creation of hash-based classes that need to be
directly JSON-serializable. Just inherit from this class, and you’ll
have the method needed for use in L<JSON>, L<Cpanel::JSON::XS>, &c.

This assumes, of course, that your object’s contents are JSON-serializable.
If that’s not true, then you’ll have trouble.

=head1 SEE ALSO

This module makes a great companion to L<Class::XSAccessor>.

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $hr = I<CLASS>->TO_JSON()

Returns a shallow copy of the object’s hash reference.

Suitable for use with L<JSON::XS> et al.

=cut

sub TO_JSON ($self) {
    return {%$self};
}

1;
