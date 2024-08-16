package Cpanel::Async::Exec::Process;

# cpanel - Cpanel/Async/Exec/Process.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::Exec::Process - interact with an C<exec(2)>ed command

=head1 SYNOPSIS

See L<Cpanel::Async::Exec>.

=head1 DESCRIPTION

This object provides real-time access to a forked subprocess—either
an in-progress one or a pending one.

(NB: Whether the process is pending or in-progress is abstracted by design.)

Instances of this class should normally survive until the child exits.
If that doesn’t happen, the child will receive SIGKILL as the class’s
DESTROY handler fires. Note that the timer for the subprocess’s timeout
contains a reference to the object, so unless you manually forgo a timeout,
you normally shouldn’t need to worry about this.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Destruct::DestroyDetector );

#----------------------------------------------------------------------
#
# Maintenance notes:
#
# The internal attributes that this object expects are:
#
#   - deferred: For when the process ends on its own.
#
#   - process_deferred: For when the process ends, however that happens.
#
#   - canceled_sr: Ref to a boolean that indicates whether the process
#       has been canceled (i.e., terminate()ed)
#
#   - pid
#
#   - watch_sr: The AnyEvent watch object for the subprocess’s “end pipe”.
#
#   - watch_sr: The AnyEvent timer object for the subprocess timeout.
#
#----------------------------------------------------------------------

=head1 METHODS

NB: This class is normally instantiated in L<Cpanel::Async::Exec>.

=head2 promise($child_error) = I<OBJ>->child_error_p()

Returns a promise that resolves to the subprocess’s C<$CHILD_ERROR>
(cf. L<perlvar/$CHILD_ERROR>), if the subprocess isn’t C<terminate()>d first.

If C<terminate()> is called before the child process ends on its own,
then the returned promise never resolves.

This promise rejects if (but only if) I<OBJ> is DESTROYed prior to the
process’s end.

=cut

sub child_error_p ($self) {
    return $self->{'child_error_p'} ||= $self->{'deferred'}->promise();
}

=head2 $obj = I<OBJ>->terminate()

“Forgets” the subprocess, forcibly terminating it if it’s already
active, or canceling it if it hasn’t started.

Behavior is undefined if the subprocess is already ended.

=cut

sub terminate ($self) {
    ${ $self->{'canceled_sr'} } = 1;

    if ( $self->{'watch_sr'} && ${ $self->{'watch_sr'} } ) {
        $self->_clean_up();

        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid( $self->{'pid'} );
    }

    return $self;
}

#----------------------------------------------------------------------

sub _clean_up ($self) {
    $self->{'process_deferred'}->resolve();
    ${ $self->{'watch_sr'} } = undef;
    ${ $self->{'timer_sr'} } = undef;

    return;
}

sub DESTROY ($self) {
    if ( $self->{'watch_sr'} && ${ $self->{'watch_sr'} } ) {
        $self->_clean_up();

        my $ref = ref $self;
        my $pid = $self->{'pid'};

        # This shouldn’t normally happen, so it’s untranslated.
        my $msg = "Process $pid outlived its parent $ref object. Killing process …";
        $self->{'deferred'}->reject($msg);

        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid( $self->{'pid'} );
    }

    $self->SUPER::DESTROY();

    return;
}

1;
