package Cpanel::UserTasks::Interface::SSEvent;

# cpanel - Cpanel/UserTasks/Interface/SSEvent.pm   Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception                                        ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure   ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::LogUpdate ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Progress  ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Success   ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Warning   ();

use Cpanel::Time::ISO ();

use parent qw{
  Cpanel::Interface::JSON
};

=encoding utf8

=head1 NAME

Cpanel::UserTasks::Interface::SSEvent - Interface to log SSE Events

=head1 SYNOPSIS

    use parent qw{ Cpanel::UserTasks::Interface::SSEvent };

    sub sse_process_log ( $sse_usertask, $log_raw ) {

        return unless length $log_raw;

        my $time2quit = __PACKAGE__->can('SUPER::sse_process_log')->( $sse_usertask, $log_raw );

        return $time2quit if $time2quit;

        ###
        ### any custom filter can go here...
        ###
        my @lines = split( "\n", $log_raw );
        foreach my $line (@lines) {

            $self->sse_update( "This is a LogUpdate event" );

            $self->sse_warning( "This is a Warning event" );

            $self->sse_failure( "This is an Error... Abort" );

            $self->sse_success( "Task Complete" );

        }

        return $time2quit;
    }

=head1 FUNCTIONS

=head2 $self->log_file

Override that function to provide the log_file to use.

Alternatively you can also provide one 'sse_log_file' function if you want to split
the SSE logs from your main log.

=cut

sub log_file {
    die Cpanel::Exception::create( 'FunctionNotImplemented', [ name => 'log_file' ] );
}

sub _log_file ($self) {

    $self->{_log_file} //= eval { $self->sse_log_file } // $self->log_file;

    return $self->{_log_file};
}

=head2 $self->sse_update( $data )

Emit to the log one SSE LogUpdate event using the provided data.

=cut

sub sse_update ( $self, $data ) {

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::LogUpdate->new(
        data => $data,
    );

    return $self->sse_log_event($event);
}

=head2 $self->sse_progress( $percentage )

Emit a Progress Event for a Progress Bar using the provided percentage [ 0..100 ]

=cut

sub sse_progress ( $self, $percentage = -1, $txt = undef ) {

    $self->{_current_progress_bar} //= -1;
    return if $percentage <= $self->{_current_progress_bar};

    $self->{_current_progress_bar} = $percentage;

    my $data = { percentage => $percentage, message => $txt // '' };

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Progress->new(
        data => $data,
    );

    return $self->sse_log_event($event);
}

=head2 $self->sse_warning( $data )

Emit to the log one SSE Warning event using the provided data.

=cut

sub sse_warning ( $self, $data ) {

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Warning->new(
        data => $data,
    );

    return $self->sse_log_event($event);
}

=head2 $self->sse_failure( $data )

Emit to the log one SSE Failure event using the provided data.

=cut

sub sse_failure ( $self, $data ) {

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure->new(
        data => $data,
    );

    return $self->sse_log_event($event);
}

=head2 $self->sse_success( $data )

Emit to the log one SSE Success event using the provided data.

=cut

sub sse_success ( $self, $data ) {

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Success->new(
        data => $data,
    );

    return $self->sse_log_event($event);
}

=head2 $self->sse_log_event( $event )

Emit to the log the SSE event provided.
Prefer using the sse_* helpers.

=cut

sub sse_log_event ( $self, $event ) {

    my $log = $self->_log_file();

    open( my $fh, '>>', $log )
      or die Cpanel::Exception::create(
        'IO::FileOpenError',
        [ 'path' => $log, 'error' => $!, 'mode' => '>' ]
      );

    my $time = Cpanel::Time::ISO::unix2iso();

    print {$fh} "$time: SSEvent " . $self->to_json($event) . "\n";
    close($fh);

    return 1;
}

=head2 sse_process_log ( $sse_usertask, $log_raw )

This helper is used by 'Cpanel::Server::SSE::cpanel::UserTasks' and provides
a filter for the log.

Only some special events are sent to the UI using the SSE mechanism.

=cut

sub sse_process_log ( $sse_usertask, $log_raw ) {

    return unless length $log_raw;

    my @lines = split( "\n", $log_raw );

    foreach my $line (@lines) {

        # parsing our own output log
        $line =~ s{^(\S+Z):\s+}{};

        next unless $line =~ s{^SSEvent\s+}{};

        my $task = __PACKAGE__->from_json($line);

        next unless ref $task;

        my $time2quit = $task->{type} && $task->{type} =~ qr{(?:fail|complete)} ? 1 : 0;

        if ( $sse_usertask->{current_task} ) {
            $task->{task_id} = $sse_usertask->{current_task};
        }

        $sse_usertask->send($task);

        return $time2quit if $time2quit;
    }

    return;    # returns 1 -> time to quit
}

1;
