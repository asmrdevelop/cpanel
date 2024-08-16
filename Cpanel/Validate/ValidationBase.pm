package Cpanel::Validate::ValidationBase;

# cpanel - Cpanel/Validate/ValidationBase.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::Exception ();

our $REQUIRED_ARGUMENT;
our $OPTIONAL_ARGUMENT;

BEGIN {
    $REQUIRED_ARGUMENT = 2;
    $OPTIONAL_ARGUMENT = 1;
}

use constant {
    VALIDATION_CONTEXTS => {
        'CPANEL'   => 1,
        'WHOSTMGR' => 2,
    },
    REQUIRED_ARGUMENT             => $REQUIRED_ARGUMENT,
    OPTIONAL_ARGUMENT             => $OPTIONAL_ARGUMENT,
    REQUIRED_OR_OPTIONAL_ARGUMENT => ( $REQUIRED_ARGUMENT | $OPTIONAL_ARGUMENT ),
};

sub VALIDATION_CONTEXT_NAMES {
    return { reverse %{ __PACKAGE__->VALIDATION_CONTEXTS() } };
}

# Override this in your consuming validation module
sub init {
    my ($self) = @_;

    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

sub validate {
    my ($self) = @_;

    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

# Validates that all of the component's required parameters were supplied
sub validate_arguments {
    my ($self) = @_;

    my $required_arguments_ar = $self->_get_validation_argument_type_array_ref(REQUIRED_ARGUMENT);
    for my $argument (@$required_arguments_ar) {
        if ( !defined $self->{$argument} ) {
            die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', [$argument] );
        }
    }

    return;
}

# Add required arguments.
sub add_required_arguments {
    my $self = shift;
    $self->_add_validation_arguments( \@_, REQUIRED_ARGUMENT );
    return;
}

# Add optional arguments.
sub add_optional_arguments {
    my $self = shift;
    $self->_add_validation_arguments( \@_, OPTIONAL_ARGUMENT );
    return;
}

# Gets an array of all the validation arguments for this validation module.
# These arguments may come from added validation components or via the method add_validation_argument
sub get_validation_arguments {
    return ( @{ $_[0]->_get_validation_argument_type_array_ref(REQUIRED_ARGUMENT) }, @{ $_[0]->_get_validation_argument_type_array_ref(OPTIONAL_ARGUMENT) } );
}

# Gets a hash of validation arguments for this validation module with the 'required' and 'optional' arguments separated.
# These arguments may come from added validation components or via the method add_validation_argument
sub get_validation_arguments_by_type {
    return (
        'required' => $_[0]->_get_validation_argument_type_array_ref(REQUIRED_ARGUMENT),
        'optional' => $_[0]->_get_validation_argument_type_array_ref(OPTIONAL_ARGUMENT),
    );
}

sub validate_context {
    my ( $self, $validation_context ) = @_;

    return 1 if !defined $validation_context;

    my $possible_contexts_hr = $self->VALIDATION_CONTEXTS();

    if ( $validation_context =~ tr{0-9}{}c || !grep { $_ & $validation_context } values %$possible_contexts_hr ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be [list_or,_2].', [ 'validation_context', [ values %$possible_contexts_hr ] ] );
    }

    my $mutually_exclusive_value = ( $possible_contexts_hr->{'CPANEL'} | $possible_contexts_hr->{'WHOSTMGR'} );
    if ( ( $validation_context & $mutually_exclusive_value ) == $mutually_exclusive_value ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” contains an invalid value. The named values “[_2]” and “[_3]” are mutually exclusive.', [ 'validation_context', 'WHOSTMGR', 'CPANEL' ] );
    }

    return 1;
}

sub is_validation_context {
    my ( $self, $validation_context ) = @_;

    if ( !defined $validation_context ) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', ['validation_context'] );
    }
    elsif ( $validation_context =~ tr{0-9}{}c ) {
        die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid [asis,validation_context].", [$validation_context] );
    }

    $self->validate_context($validation_context);

    if ( !$self->{'validation_context'} ) {
        return 1 if $validation_context == $self->VALIDATION_CONTEXTS()->{'CPANEL'};
        return 0;
    }
    elsif ( ( $self->{'validation_context'} & $validation_context ) == $validation_context ) {
        return 1;
    }

    return 0;
}

sub is_whm_context {
    return $_[0]->is_validation_context( $_[0]->VALIDATION_CONTEXTS()->{'WHOSTMGR'} );
}

sub has_root {
    my ($self) = @_;

    if ( $self->is_whm_context() ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        return Whostmgr::ACLS::hasroot();
    }
    return 0;
}

sub _validate_argument_value {
    return ( ( $_[1] & REQUIRED_OR_OPTIONAL_ARGUMENT ) == $_[1] ) ? 1 : 0;
}

1;
