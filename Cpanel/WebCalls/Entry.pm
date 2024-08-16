package Cpanel::WebCalls::Entry;

# cpanel - Cpanel/WebCalls/Entry.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Entry

=head1 SYNOPSIS

See end classes.

=head1 DESCRIPTION

This class provides object accessors and JSON serializability for
cPanel webcall entries. It’s a base class, meant to be subclassed per
each webcall type (e.g., C<DynamicDNS>).

It’s normally created from L<Cpanel::WebCalls::Entry::Read>.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Hash::JSONable',
    'Cpanel::Destruct::DestroyDetector',
);

use Class::XSAccessor (
    getters => [
        'created_time',
        'last_update_time',
    ],
);

#----------------------------------------------------------------------

=head1 ACCESSORS

=over

=item * C<created_time> (ISO/Z format)

The time at which the webcall was created.

=item * C<last_update_time> (ISO/Z format)

The time at which the webcall last updated local configuration.

=item * C<last_run_times> (list of ISO/Z format, or the count thereof
in scalar context)

The times (I<plural!>) at which the webcall most recently ran.

=back

=cut

# Implemented as a subroutine so that we return a list
# rather than an array reference.
sub last_run_times ($self) {
    return @{ $self->{'last_run_times'} };
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $type = I<CLASS>->type()

(Callable as a class or instance method.)

A convenience method that returns the “type” of a class or object,
usually deduced by removing the present namespace from the beginning
of I<CLASS>.

=cut

sub type ($obj) {
    my $class = ref($obj) || $obj;

    _die_if_not_subclass($class);

    my $pkg = __PACKAGE__;
    $class =~ s<\A\Q$pkg\E::><> or die "Invalid class: $class";

    return $class;
}

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $obj = I<CLASS>->adopt( \%PARSE )

Converts an existing hash reference (i.e., in-place) into a I<CLASS>
instance.

%PARSE contains all of the data for the L</ACCESSORS> above.
(C<last_run_times> B<MUST> be an array reference.)

=cut

sub adopt ( $class, $parse_hr ) {
    _die_if_not_subclass($class);

    return bless $parse_hr, $class;
}

sub _die_if_not_subclass ($class) {
    if ( $class eq __PACKAGE__ ) {
        require Carp;
        Carp::croak("$class is a base class!");
    }

    return;
}

1;
