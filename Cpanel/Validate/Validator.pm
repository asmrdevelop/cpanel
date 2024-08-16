package Cpanel::Validate::Validator;

# cpanel - Cpanel/Validate/Validator.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use base qw (
  Cpanel::Validate::ValidationBase
);

use Cpanel::Exception ();

our $INTERNAL_ARGUMENT;
our $USER_PROVIDED_ARGUMENT;

BEGIN {
    $INTERNAL_ARGUMENT      = 4;
    $USER_PROVIDED_ARGUMENT = 8;
}
use constant {
    NOT_SYSTEM_ARGUMENT    => $USER_PROVIDED_ARGUMENT | $INTERNAL_ARGUMENT,
    INTERNAL_ARGUMENT      => $INTERNAL_ARGUMENT,
    USER_PROVIDED_ARGUMENT => $USER_PROVIDED_ARGUMENT,
    OPTIONAL_ARGUMENT      => $Cpanel::Validate::ValidationBase::OPTIONAL_ARGUMENT,
    REQUIRED_ARGUMENT      => $Cpanel::Validate::ValidationBase::REQUIRED_ARGUMENT,

};

sub new {
    my ( $class, @args ) = @_;

    my $self = bless {
        'validation_arguments' => {},
        'components'           => [],
    }, $class;

    $self->init(@args);

    return $self;
}

# Override this in your consuming validation module
sub init {
    my ($self) = @_;

    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

# Will call the validate methods for each of the validation components assigned to the validation module
sub validate {
    $_->validate() for @{ $_[0]->{'components'} };
    return;
}

# Adds a validation component to this validation module
#   NOTE: Order is preserved and may be used to order validation checks
sub add_validation_component {
    my ( $self, $validation_component ) = @_;
    if ( !$validation_component->isa('Cpanel::Validate::Component') ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Validation components must be of type “[_1]”!', ['Cpanel::Validate::Component'] );
    }

    push @{ $self->{'components'} }, $validation_component;

    my %validation_arguments = $validation_component->get_validation_arguments_by_type();

    $self->add_required_arguments( @{ $validation_arguments{'required'} } ) if @{ $validation_arguments{'required'} };
    $self->add_optional_arguments( @{ $validation_arguments{'optional'} } ) if @{ $validation_arguments{'optional'} };

    return;
}

# Adds several validation components at once
#   NOTE: Order is preserved and may be used to order validation checks
sub add_validation_components {
    $_[0]->add_validation_component($_) for @_[ 1 .. $#_ ];
    return;
}

# Gets an array of validation components assigned to the validation module.
sub get_validation_components {
    return @{ $_[0]->{'components'} };
}

# Add internal arguments. Internal arguments are those that are required by a validation component,
# but are supplied during the initialization of the validator. Since the validator supplies these to
# the validation components, we do not need to display that they are required or optional arguments.
sub add_internal_arguments {
    my $self = shift;
    $self->_add_validation_arguments( \@_, INTERNAL_ARGUMENT );
    return;
}

# Add user provided arguments. User provided argument input will be quarantined from other inputs as we do
# not want to allow user provided parameters to bleed into system provided ones. Any parameter NOT marked
# as user provided is assumed to be system provided.
sub add_user_provided_arguments {
    my $self = shift;
    $self->_add_validation_arguments( \@_, USER_PROVIDED_ARGUMENT );
    return;
}

sub get_user_provided_arguments {
    return @{ $_[0]->_get_validation_argument_type_array_ref(USER_PROVIDED_ARGUMENT) };
}

sub get_system_provided_arguments {
    return ( grep { !( $_[0]->{'validation_arguments'}{$_} & NOT_SYSTEM_ARGUMENT ) } keys %{ $_[0]->{'validation_arguments'} } );
}

# Add a user provided argument. User provided argument input will be quarantined from other inputs as we do
# not want to allow user provided parameters to bleed into system provided ones. Any parameter NOT marked
# as user provided is assumed to be system provided.
sub add_user_provided_argument {
    return $_[0]->_add_validation_arguments( [ $_[1] ], USER_PROVIDED_ARGUMENT );
}

# Adds validation arguments in addition those that are provided by the validation components
sub _add_validation_arguments {
    my ( $self, $args_ar, $value ) = @_;

    die Cpanel::Exception::create_raw( 'MissingParameter', 'No validation arguments arrayref were specified.' ) if !ref $args_ar;
    if ( !$self->_validate_argument_value($value) ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The argument value is not in the expected form. Please use one of the following: [join,~, ,_1]',
            [
                [
                    OPTIONAL_ARGUMENT,
                    REQUIRED_ARGUMENT,
                    INTERNAL_ARGUMENT,
                    USER_PROVIDED_ARGUMENT,
                ],
            ],
        );
    }

    foreach my $arg (@$args_ar) {
        if ( my $current_value = $self->{'validation_arguments'}{$arg} ) {
            if ( $value == OPTIONAL_ARGUMENT && ( $current_value & REQUIRED_ARGUMENT ) == $current_value ) {
                next;
            }
            if ( $value == REQUIRED_ARGUMENT && ( $current_value & OPTIONAL_ARGUMENT ) == $current_value ) {
                $current_value ^= OPTIONAL_ARGUMENT;
            }
            $self->{'validation_arguments'}{$arg} = $current_value | $value;
        }
        else {
            $self->{'validation_arguments'}{$arg} = $value;
        }
    }

    return;
}

# Internal arguments will be excluded unless specifically asked for.
sub _get_validation_argument_type_array_ref {
    my ( $self, $argument_type ) = @_;

    my $validation_type_hash = $self->_get_validation_argument_type_hash($argument_type);

    # need to validate arguments in a consistent order
    return [ sort keys %{$validation_type_hash} ];
}

# Internal arguments will be excluded unless specifically asked for.
sub _get_validation_argument_type_hash {
    my ( $self, $argument_type ) = @_;

    if ( $argument_type == INTERNAL_ARGUMENT ) {
        return {
            map {
                my $value = $self->{'validation_arguments'}{$_};
                ( ( $value & $argument_type ) == $argument_type ) ? ( $_ => $value ) : ()
            } keys %{ $self->{'validation_arguments'} }
        };
    }
    else {
        return {
            map {
                my $value = $self->{'validation_arguments'}{$_};
                ( ( $value & $argument_type ) && !( $value & INTERNAL_ARGUMENT ) ) ? ( $_ => $value ) : ()
            } keys %{ $self->{'validation_arguments'} }
        };
    }
}

# This is in a tight loop 500k+ calls
sub _validate_argument_value {
    return ( !( ( $_[1] & NOT_SYSTEM_ARGUMENT ) == $_[1] ) && !$_[0]->SUPER::_validate_argument_value( $_[1] ) )
      ? 0
      : 1;
}

1;
