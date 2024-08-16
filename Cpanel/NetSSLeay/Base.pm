package Cpanel::NetSSLeay::Base;

# cpanel - Cpanel/NetSSLeay/Base.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::Base - Base class for C<Cpanel::NetSSLeay::*>

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

L<Net::SSLeay> is a thin, simple wrapper around OpenSSL. This provides
an object interface atop the objects that that library exposes.

One significant benefit is management of allocated resources, which
should prevent memory leaks.

It’s not intended to be complete; the idea is just to be as complete
as cPanel needs.

=head1 GUIDELINES FOR EXPANSIONS

This set of modules is a convenience layer merely; it does B<NOT>
absolve the caller of the responsibility to understand OpenSSL.

=over

=item * Name object methods consistently with their OpenSSL
and Net::SSLeay equivalents. For example, L<Cpanel::NetSSLeay::X509_STORE>
exposes an C<add_cert()> method that calls C<X509_STORE_add_cert()>.

=item * Don’t document things that come from OpenSSL.

=item * Use L<Cpanel::NetSSLeay>’s C<do()> function to simplify
error-checking. This achieves consistent error reporting via
L<Cpanel::Exception>-based exceptions.

=item * Return the object if the underlying Net::SSLeay function
doesn’t return anything useful (other than indicating success/failure).

=back

=head1 SUBCLASS INTERFACE

Every subclass B<MUST> implement:

=over

=item * C<_new_func()> - A constant or sub that returns the name of a
Net::SSLeay function to call to allocate a resource.

=item * C<_free_func()> - Like C<_new_func()> but to free the object
instead.

=back

The following are available to subclasses:

=over

=item * C<_Set_To_Destroy()> - Sets the object to free the Net::SSLeay
resource on DESTROY. Useful if the object was created with C<new_wrap()>
(see below).

=back

=cut

#----------------------------------------------------------------------

use Cpanel::NetSSLeay ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( @ARGS )

Allocates the resource. @ARGS are given to whichever function
the C<_new_func()> method names.

The resource will be freed once $obj is DESTROYed.

=cut

sub new {
    my ( $class, @args ) = @_;

    my $raw = Cpanel::NetSSLeay::do( $class->_new_func(), @args );

    my $self = $class->new_wrap($raw);

    #set the destroy flag
    $self->[1] = 1;

    return $self;
}

=head2 $obj = I<CLASS>->new_wrap( $PTR )

Wraps a (numeric) pointer to an existing, pre-allocated resource.

Unlike with C<new()>, the resource will B<NOT> be freed when the
returned $obj is DESTROYed.

=cut

sub new_wrap {

    #Perl segfaults on DESTROY when a scalar ref is used here.
    return bless [ $_[1] ], $_[0];
}

#protected
sub _Set_To_Destroy {
    $_[0][1] = 1;

    return $_[0];
}

sub DESTROY {
    my ($self) = @_;

    if ( $self->[1] ) {
        Cpanel::NetSSLeay::do( $self->_free_func(), $self->[0] );
    }

    return;
}

#----------------------------------------------------------------------

=head1 $obj = I<OBJ>->leak()

Sets I<OBJ> so that it will I<NOT> free its Net::SSLeay resource
upon DESTROY.

Only call this if OpenSSL itself will free the resource; otherwise
you’ll cause a memory C<leak()>.

=cut

sub leak ($self) {
    $self->[1] = undef;

    return $self;
}

=head1 $ptr = I<OBJ>->PTR()

Returns a numeric pointer to the Net::SSLeay resource that OBJ
represents.

B<IMPORTANT:> Try not to need this except in subclasses of this class. The
idea of the Cpanel::NetSSLeay::* classes is to abstract away the pointer
stuff so that callers don’t have to worry about cleanup and have a
(hopefully) more intuitive syntax to work with than Net::SSLeay provides.

Consider whether a new wrapper method would make more sense in that light
rather than creating another call into this method.

=cut

sub PTR {
    return $_[0][0];
}

1;
