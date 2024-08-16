package Cpanel::Hash::ForObject;

# cpanel - Cpanel/Hash/ForObject.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Hash::ForObject - Protection against direct hash access

=head1 SYNOPSIS

    package MyObject;

    sub new ($class) {
        my $self = bless {}, $class;

        tie %$self, 'Cpanel::Hash::ForObject', $class;

        return $self;
    }

    sub do_the_thing ($self) {

        # This works:
        $self->{'foo'} = 123;

        # ...
    }

… then later on:

    package main;

    my $obj = MyObject->new();

    my $contraband = $obj->{'foo'};   # boom!

=head1 DESCRIPTION

This class implements a tie for hashes that forbids access to the hashes
except from an approved class. This is useful, e.g., to ensure that cPanel
code only interacts with a blessed hashref via object methods.

=head1 ALGORITHM

When the hash is C<tie()>d, a single namespace should be passed in.
That namespace is stored internally as the hash’s “internal” namespace.

On each call to the object’s tie methods (e.g., C<FETCH>—see
L<perltie/Tying Hashes> for more details) the following check happens:

=over

=item 1) If the caller was the hash’s internal namespace or a superclass
thereof, allow the method to run.

=item 2) If the caller is outside the cPanel namespaces (see this
module’s code for how we determine this), allow the method to run.

=item 3) Throw an exception. Since this is an internal error, the exception
includes a stack trace.

=back

=cut

#----------------------------------------------------------------------

use cPstrict;

use Carp      ();
use Tie::Hash ();

use parent -norequire => 'Tie::StdHash';

use constant _CP_NAMESPACES => (
    'Cpanel',
    'Whostmgr',
    'bin',
    'scripts',
    't',
);

my %OBJ_CALLERPKG;

#----------------------------------------------------------------------

sub TIEHASH ( $class, $callerpkg ) {
    my $self = $class->SUPER::TIEHASH();

    $OBJ_CALLERPKG{$self} = $callerpkg;

    return $self;
}

BEGIN {
    no strict 'refs';
    for my $method (qw( FETCH STORE EXISTS DELETE CLEAR FIRSTKEY NEXTKEY )) {
        *{$method} = sub ( $self, @args ) {

            my $caller = ( caller 0 )[0];

            $self->_ensure_caller($caller);

            my $methodname = "SUPER::$method";

            return $self->$methodname(@args);
        };
    }
}

sub DESTROY ($self) {
    delete $OBJ_CALLERPKG{$self};

    return;
}

sub _ensure_caller ( $self, $caller ) {

    my $ok = $OBJ_CALLERPKG{$self}->isa($caller);

    # If the caller appears to be outside cP then allow it through:
    $ok ||= !grep { 0 == rindex( $caller, "${_}::", 0 ) } _CP_NAMESPACES;

    Carp::confess "$self: Use methods!" if !$ok;

    return;
}

1;
