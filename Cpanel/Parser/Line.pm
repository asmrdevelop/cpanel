package Cpanel::Parser::Line;

# cpanel - Cpanel/Parser/Line.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is an abstract class. It requires implementation of:
#
#process_line()
#process_error_line()
#
#...to function correctly.
#----------------------------------------------------------------------

use strict;

my $idx;

sub process_data {
    my ( $self, $data ) = @_;

    if ( length $self->{'_buffer'} ) {
        substr( $data, 0, 0, $self->{'_buffer'} );
    }

    while ( -1 != ( $idx = index( $data, "\n" ) ) ) {
        $self->process_line( substr( $data, 0, 1 + $idx, '' ) ) || return 0;
    }

    $self->{'_buffer'} = $data;

    return 1;
}

sub process_error_data {
    my ( $self, $data ) = @_;

    if ( length $self->{'_error_buffer'} ) {
        substr( $data, 0, 0, $self->{'_error_buffer'} );
    }

    while ( -1 != ( $idx = index( $data, "\n" ) ) ) {
        $self->process_error_line( substr( $data, 0, 1 + $idx, '' ) ) || return 0;
    }

    $self->{'_error_buffer'} = $data;

    return 1;
}

sub clear_buffer {
    my ($self) = @_;

    $self->{'_buffer'} = '';

    return;
}

sub clear_error_buffer {
    my ($self) = @_;

    $self->{'_error_buffer'} = '';

    return;
}

1;
