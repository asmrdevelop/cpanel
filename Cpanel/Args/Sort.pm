package Cpanel::Args::Sort;

# cpanel - Cpanel/Args/Sort.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::Args::Meta
);

use Cpanel::Exception         ();
use Cpanel::Args::Sort::Utils ();

#----------------------------------------------------------------------
# NOTE: This module is "pickier" about its arguments than UAPI
# itself is. See the notes in Cpanel/Args.pm.
#----------------------------------------------------------------------

#Named args to pass in a hashref:
#   column  (required, must not be q{})
#   reverse (undef, 0, or 1; defaults to 0)
#   method  (required)
sub new {
    my ( $class, $args_hr ) = @_;

    #This will produce an exception later on.
    local $args_hr->{'column'} = undef if !length $args_hr->{'column'};

    my $method = $args_hr->{'method'};

    if ( !Cpanel::Args::Sort::Utils::is_valid_sort_method($method) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid sort method.', [$method] );
    }

    if ( $args_hr->{'reverse'} && $args_hr->{'reverse'} ne '1' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be empty or one of the following values: [join, ,_2]', [ 'reverse', [ 0, 1 ] ] );
    }

    my $self = __PACKAGE__->can('SUPER::new')->( $class, $args_hr );

    $self->{'_reverse'} = $self->{'_reverse'} ? 1 : 0;

    return $self;
}

sub _required_args {
    return qw( column method );
}

sub method {
    my ($self) = @_;
    return $self->{'_method'};
}

sub reverse {
    my ($self) = @_;
    return $self->{'_reverse'};
}

sub column {
    my ($self) = @_;
    return $self->{'_column'};
}

sub apply {
    my ( $self, $records_ar ) = @_;

    my $column = $self->{'_column'};

    my $full_method = $self->method() . ( $self->reverse() ? '_reverse' : q{} );
    Cpanel::Args::Sort::Utils::sort_by_column_and_method( $records_ar, $column, $full_method );

    return $records_ar;
}

1;
