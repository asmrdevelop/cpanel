package Cpanel::Validate::Component;

# cpanel - Cpanel/Validate/Component.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use base qw (
  Cpanel::Validate::ValidationBase
);

my %KEYMAP = (
    $Cpanel::Validate::ValidationBase::REQUIRED_ARGUMENT => 'required_arguments',
    $Cpanel::Validate::ValidationBase::OPTIONAL_ARGUMENT => 'optional_arguments'
);

use Cpanel::Exception ();

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {
        'required_arguments' => [],
        'optional_arguments' => []
    }, $class;

    $self->init(%OPTS);

    return $self;
}

# Adds validation arguments
sub _add_validation_arguments {
    my ( $self, $args_ar, $value ) = @_;

    die Cpanel::Exception::create_raw( 'MissingParameter', 'No validation arguments arrayref were specified.' ) if !ref $args_ar;

    if ( !$self->SUPER::_validate_argument_value($value) ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The argument value is not in the expected form. Please use “[_1]” or “[_2]”.',
            [
                $Cpanel::Validate::ValidationBase::OPTIONAL_ARGUMENT,
                $Cpanel::Validate::ValidationBase::REQUIRED_ARGUMENT,
            ],
        );
    }

    push @{ $self->{ $KEYMAP{$value} } }, @$args_ar;

    return;
}

sub _get_validation_argument_type_array_ref {
    return $_[0]->{ $KEYMAP{ $_[1] } } || ();
}

1;
