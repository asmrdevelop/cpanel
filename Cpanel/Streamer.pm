package Cpanel::Streamer;

# cpanel - Cpanel/Streamer.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Streamer - base class for streaming applications

=head1 SYNOPSIS

    package My::Streamer;

    use parent qw( Cpanel::Streamer );

    sub _init {
        my ($self, @args) = @_;

        ...;
    }

    #----------------------------------------------------------------------

    package main;

    my $streamer = My::Streamer->new();

    #Return is Perl’s $CHILD_ERROR.
    my $child_error = $streamer->waitpid_nohang();
    $child_error = $streamer->waitpid();
    $child_error = $streamer->terminate();

    my $from_fh = $streamer->get_attr('from');

=head1 DESCRIPTION

This base class encapsulates logic for streaming applications, i.e.,
applications that run in a separate process and that communicate
with via an input and an output stream.

An instance of this class will forcibly C<terminate()> its child process
if the instance goes out of scope and the child process is still alive.

=head1 HOW TO CREATE A SUBCLASS OF THIS MODULE

You must create an C<_init()> method in your subclass.
This method will receive as arguments whatever C<new()> receives
(key-value pairs are suggested but not required)
and must set the following L<Cpanel::AttributeProvider> attributes:

=over

=item * C<pid> The process that does the actual application.

=item * C<from> A Perl filehandle for reading data “from” the
application process.

=item * C<to> A Perl filehandle for writing data “to” the
application process.

=back

=cut

use parent qw( Cpanel::AttributeProvider );

use Cpanel::Kill::Single ();

=head1 METHODS

=head2 I<CLASS>->new()

Returns an instance of the class.

=cut

sub new {
    my ( $class, @args ) = @_;

    my $self = $class->SUPER::new();

    $self->set_attr( ppid => $$ );

    $self->_init(@args);

    return $self;
}

=head2 $CHILD_ERROR = I<OBJ>->waitpid()

Waits for the child process to end and returns Perl’s C<$CHILD_ERROR>.

=cut

sub waitpid {
    my ($self) = @_;

    return $self->_do_waitpid(0);    #!nohang aka blocking
}

=head2 $CHILD_ERROR = I<OBJ>->waitpid_nohang()

Returns Perl’s C<$CHILD_ERROR> if the child process is ready to be
reaped, or undef if the child process isn’t reapable yet.

=cut

sub waitpid_nohang {
    my ($self) = @_;

    return $self->_do_waitpid(1);    #nohang aka non-blocking
}

=head2 $CHILD_ERROR = I<OBJ>->terminate()

Forcibly ends the child process via L<Cpanel::Kill::Single>’s
C<safekill_single_pid()> function. Returns Perl’s C<$CHILD_ERROR>.

=cut

sub terminate {
    my ($self) = @_;

    my $child_err;

    if ( !$self->_check_already_ended() ) {
        $self->{'_ended'} = 'kill';

        $child_err = Cpanel::Kill::Single::safekill_single_pid( $self->get_attr('pid') );
    }

    return $child_err;
}

sub DESTROY {
    my ($self) = @_;

    return if $$ != $self->get_attr('ppid') || !defined $self->get_attr('pid');

    my $need_to_kill = !$self->{'_ended'};
    $need_to_kill &&= kill( 'ZERO', $self->get_attr('pid') );

    if ($need_to_kill) {
        warn "$self DESTROY()ed while child process still lives! Terminating …";
        $self->terminate();

        #We do NOT close the filehandle right away
        #after reaping because there may still be data
        #in the buffer. For example, the shell’s final
        #"\nlogout\n" might not reach the user.
    }

    return;
}

sub _do_waitpid {
    my ( $self, $nohang_yn ) = @_;

    my $c_err;

    if ( !$self->_check_already_ended() ) {

        my $cpid = $self->get_attr('pid');

        local $?;
        if ( CORE::waitpid $cpid, $nohang_yn ) {
            $c_err = $?;
            $self->{'_ended'} = 'waitpid';
        }
    }

    return $c_err;
}

sub _check_already_ended {
    my ($self) = @_;

    if ( $self->{'_ended'} ) {
        warn "Already finished $self ($self->{'_ended'})!";
        return 1;
    }

    return 0;
}

1;
