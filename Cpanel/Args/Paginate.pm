package Cpanel::Args::Paginate;

# cpanel - Cpanel/Args/Paginate.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::Args::Meta
);

use Cpanel::Exception ();

#----------------------------------------------------------------------
# NOTE: This module is "pickier" about its arguments than UAPI
# itself is. See the notes in Cpanel/Args.pm.
#----------------------------------------------------------------------

#Accepts a hashref of named parameters (both required):
#   start   0-based index of the pagination
#   size    page size
sub new {
    my ( $class, $args_hr ) = @_;

    my $self = __PACKAGE__->can('SUPER::new')->( $class, $args_hr );

    my $start = $self->{'_start'};
    if ( !length($start) || $start =~ tr{0-9}{}c ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be a nonnegative integer.', ['start'] );
    }

    my $size = $self->{'_size'};
    if ( !$size || $size =~ tr{0-9}{}c || $size < 1 ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be a positive integer.', ['size'] );
    }

    return $self;
}

sub _required_args {
    return qw( start  size );
}

#0-indexed
sub start {
    return $_[0]->{'_start'};
}

sub size {
    return $_[0]->{'_size'};
}

sub apply {
    my ( $self, $records_ar ) = @_;

    my $total_results = scalar @$records_ar;

    if ( $self->start() > $total_results ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The start index ([_1]) is larger than the total number of results ([_2]).', [ $self->start(), $total_results ] );
    }

    @$records_ar = splice @$records_ar, $self->start(), $self->size();

    return $total_results;
}

1;
