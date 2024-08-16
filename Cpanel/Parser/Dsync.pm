package Cpanel::Parser::Dsync;

# cpanel - Cpanel/Parser/Dsync.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Parser::Base';

sub new {
    my ($class) = @_;

    my $self = { 'percent' => 0, 'count' => undef, 'success' => 0 };

    return bless $self, $class;
}

sub process_error_line {
    my ( $self, $line ) = @_;

    return print STDERR $line;
}

sub process_line {
    my ( $self, $line ) = @_;
    $self->output($line);
    return 1;
}

sub finish {
    my ($self) = @_;

    $self->process_line( $self->{'_buffer'} ) if length $self->{'_buffer'};

    if ( $self->{'percent'} < 100 ) {
        $self->{'percent'} = 100;
        $self->output("…$self->{'percent'} % …\n");
    }

    $self->clear_buffer();
    $self->clear_error_buffer();

    return 1;
}

1;
