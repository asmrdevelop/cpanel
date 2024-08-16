package Cpanel::Output::Container::MethodProvider;

# cpanel - Cpanel/Output/Container/MethodProvider.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Output::Container::MethodProvider

=head1 DESCRIPTION

This is a subclass of L<Cpanel::Output::Container> that adds some
frequently-used methods for logger-type objects.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Output::Container );

#----------------------------------------------------------------------

=head2 I<OBJ>->success( $MESSAGE )

Log a success-level message.

=cut

sub success ( $self, @args ) {
    return $self->{'_logger'}->success(@args);
}

#----------------------------------------------------------------------

=head2 I<OBJ>->info( $MESSAGE )

Log an info-level message.

=cut

sub info ( $self, @args ) {
    return $self->{'_logger'}->info(@args);
}

#----------------------------------------------------------------------

=head2 I<OBJ>->warn( $MESSAGE )

Log a warn-level message.

=cut

sub warn ( $self, @args ) {
    return $self->{'_logger'}->warn(@args);
}

#----------------------------------------------------------------------

=head2 I<OBJ>->error( $MESSAGE )

Log an error-level message.

=cut

sub error ( $self, @args ) {
    return $self->{'_logger'}->error(@args);
}

1;
