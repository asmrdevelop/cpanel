package Cpanel::CommandStream::Client::Response::exec;

# cpanel - Cpanel/CommandStream/Client/Response/exec.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Response::exec

=head1 SYNOPSIS

    # Let $client be a Cpanel::CommandStream::Client::WebSocket instance:

    $client->exec(
        command => [ '/bin/echo', 'hello' ],
    )->then( sub ($resp) {
        print $resp->stdout();
    } );

=head1 DESCRIPTION

A response-object counterpart to
L<Cpanel::CommandStream::Client::Request::exec>.

This subclasses L<Cpanel::ChildErrorStringifier>, so useful methods like
C<autopsy()> and C<die_if_error()> are here.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::ChildErrorStringifier';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

%OPTS are:

=over

=item * C<stdout> - Standard output. If not given or undef,
C<stdout()> will throw an exception.

=item * C<stderr> - Like C<stdout> but for standard error.

=item * C<status> - The exit status, as packed in Perl’s C<$?>.

=item * C<program> - The name of the program that was run.
(Used in generating error messages.)

=back

=cut

sub new ( $class, %opts ) {
    return bless \%opts, $class;
}

=head2 $string = I<OBJ>->stdout()

Returns the constructor’s C<stdout>, or throws an error if none
was given.

=cut

sub stdout ($self) {
    return $self->{'stdout'} // die 'No standard output!';
}

=head2 $string = I<OBJ>->stderr()

Like C<stdout()> but for the constructor’s C<stderr>.

=cut

sub stderr ($self) {
    return $self->{'stderr'} // die 'No standard error!';
}

=head2 $status = I<OBJ>->CHILD_ERROR()

Returns the C<status> given to the constructor.

=cut

sub CHILD_ERROR ($self) {
    return $self->{'status'};
}

=head2 $status = I<OBJ>->program()

Returns the C<program> given to the constructor.

=cut

sub program ($self) {
    return $self->{'program'};
}

#----------------------------------------------------------------------

sub _extra_error_args_for_die_if_error ($self) {
    return (
        stdout => $self->stdout(),
        stderr => $self->stderr(),
    );
}

1;
