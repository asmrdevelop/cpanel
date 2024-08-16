package Cpanel::CommandStream::Client::TransportBase;

# cpanel - Cpanel/CommandStream/Client/TransportBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::TransportBase

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This module exposes transport-neutral logic that’s useful for
“transport-complete” client modules like
L<Cpanel::CommandStream::Client::WebSocket::Base>.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Destruct::DestroyDetector',
);

use Cpanel::Async::PromiseTracker ();

#----------------------------------------------------------------------

=head1 PROTECTED METHODS

=head2 promise($exec_result) = I<CLASS>->_Exec(%OPTS)

The “workhorse” method that executes a remote command.

%OPTS are:

=over

=item * C<command> - array ref of program to run and args

=item * C<stdout> - a callback to run on each standard output chunk

=item * C<stderr> - like C<stdout> but for standard error

=item * C<before_exec_cr> - optional, coderef to run before sending
the request

=back

The returned promise resolves to the resolution of
L<Cpanel::CommandStream::Request::exec>’s C<promise()> method.

This is ultimately convenience logic; it may be useful to refactor it
at some point such that it doesn’t load if it’s unneeded.

=cut

sub _Exec ( $self, %opts ) {
    my $promise_tracker = $self->_Get_promise_tracker();

    return $self->_Get_requestor_p()->then(
        sub ($requestor) {
            $opts{'before_exec_cr'}->() if $opts{'before_exec_cr'};

            my $exec = $requestor->request(
                'exec',
                command => $opts{'command'},
            );

            my @subscrs = (
                $exec->create_stdout_subscription( $opts{'stdout'} ),
                $exec->create_stderr_subscription( $opts{'stderr'} ),
            );

            # This is here for legacy reasons; in newer client modules
            # this should happen in the request object itself.
            my $registered_p = $promise_tracker->add( $exec->promise() );

            return $registered_p->finally(
                sub {
                    @subscrs = ();
                }
            );
        }
    );
}

=head2 $tracker = I<OBJ>->_Get_promise_tracker()

Returns I<OBJ>’s internal L<Cpanel::Async::PromiseTracker> instance.

=cut

sub _Get_promise_tracker ($self) {
    return $self->{'_promise_tracker'} ||= Cpanel::Async::PromiseTracker->new();
}

1;
