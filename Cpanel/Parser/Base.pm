package Cpanel::Parser::Base;

# cpanel - Cpanel/Parser/Base.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Parser::Base

=head1 DESCRIPTION

This module implements basic functionality for parser-like objects.

This documentation postdates the implementation and does not describe
it fully; please see the code for details.

=head1 SUBCLASS INTERFACE

Every subclass B<MUST> implement:

=over

=item * C<process_line($STR)>

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Parser::Line';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new {
    my ($class) = @_;

    my $self = { 'success' => 0 };

    return bless $self, $class;
}

=head2 $printed = I<OBJ>->process_error_line( $STR )

Writes $STR to STDERR.

=cut

sub process_error_line {

    # $_[0]: self
    # $_[1]: line
    return print STDERR $_[1];
}

=head2 $printed = I<OBJ>->output( $STR )

Writes $STR to the default output filehandle. This may or may not be STDOUT;
see L<perfunc/select> for details.

=cut

sub output {

    # $_[0]: self
    # $_[1]: line
    return print $_[1];
}

=head2 $success_yn = I<OBJ>->finish()

Flushes buffers then returns the object’s success value.

=cut

sub finish {
    my ($self) = @_;

    $self->process_line( $self->{'_buffer'} );

    $self->clear_buffer();

    return exists $self->{'success'} ? $self->{'success'} : 1;
}

1;
