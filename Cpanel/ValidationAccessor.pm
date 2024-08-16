
# cpanel - Cpanel/ValidationAccessor.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ValidationAccessor;

use strict;
use base 'Class::Accessor';
use Carp ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::ValidationAccessor

=head1 SYNOPSIS

  use Cpanel::ValidationAccessor 'antlers';
  has md5 => ( is => 'rw' );
  sub validate_md5 {
      my ($self, $newvalue) = @_;
      return $newvalue =~ /^[0-9a-f]{32}$/;
  }

=head1 DESCRIPTION

This is a subclass of Class::Accessor. The only difference is that it supports
validation of attributes both during the construction phase and when values
are changed via the accessors.

In order to write a validator for an attribute, create a method called
validate_<attributename>. It must accept $self plus the value being assigned.

On validation failure your method should:

  - Die with a message if you care to explain what went wrong.

  - Return false if you want a generic exception to be thrown.

On success it should:

  - Return true.

=cut

sub new {
    my ( $package, $attributes, $garbage ) = @_;

    if ($garbage) {

        # It's easy to forget that Class::Accessor (and therefore also Cpanel::ValidationAccessor) requires a hash ref.
        Carp::croak('The constructor call here is invalid. Make sure you pass a hash ref, not just bare key/value pairs.');
    }

    $attributes ||= {};

    my $self = {%$attributes};
    bless $self, $package;
    my $validation_enabled = $self->can('VALIDATION') ? $self->VALIDATION : 1;

    for my $attr ( keys %$attributes ) {
        my $value     = $attributes->{$attr};
        my $validator = $validation_enabled && $package->can( 'validate_' . $attr );
        if ( $validator && !$validator->( $self, $value ) ) {
            Carp::confess lh()->maketext( 'The value “[_1]” entered for “[_2]” is invalid.', $value, $attr );
        }
    }
    return $self;
}

sub make_accessor {
    my ( $package, $attr ) = @_;

    return sub {
        my @args = @_;
        my $self = shift @args;

        if (@args) {
            my $newvalue = shift @args;

            my $validation_enabled = $self->can('VALIDATION') ? $self->VALIDATION : 1;
            my $validator          = $validation_enabled && $package->can( 'validate_' . $attr );

            # The validator may either die or return false on failure. If it returns false, a generic error will be provided.
            if ( $validator && !$validator->( $self, $newvalue ) ) {
                Carp::confess lh()->maketext( 'The value “[_1]” entered for “[_2]” is invalid.', $newvalue, $attr );
            }
            return $self->set( $attr, $newvalue );
        }

        return $self->get($attr);
    };
}

1;
