package Cpanel::UserTasks;

# cpanel - Cpanel/UserTasks.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::UserTasks

=head1 SYNOPSIS

    require Cpanel::UserTasks;

    my $ut = Cpanel::UserTasks->new();

    my $task_id = $ut->add(
        'subsystem' => 'some_subsystem',
        'action'    => 'create',
        'args'      => {
            'a' => 'howdy',
            'b' => 'there',
            'c' => 'pardner'
        },

        ## optional

        # only run a single task for that <subsystem>::<action> at the same time
        exclusive => 1,

        # or use your own key

        # multiple tasks for <subsystem>::<action> can run at the same time but only one tagged with <howdy>
        exclusive => 'some_subsystem-create-howdy'

    );

    my $contents = $ut->get($task_id);

    $ut->remove($task_id);

=head1 DESCRIPTION

C<Cpanel::UserTasks> is a user-facing task queue, for long-running
tasks.  It uses the C<Directory::Queue::Normal> as its queueing
system, and adds the automatic starting of a runner program when tasks
are added to its queue.

=cut

use cPstrict;

use parent 'Directory::Queue::Normal';

use Carp                         ();
use Cpanel::UserTasksCore::Task  ();
use Cpanel::UserTasksCore::Utils ();

=head1 VARIABLES

=head2 $MAX_SLEEP

The maximum amount of time to sleep in order to acquire a lock.
Default is 50000µs.

=cut

our $MAX_SLEEP = 500_000;

=head2 $SLEEP

The amount of time for an individual sleep, in order to acquire a
lock.  Default is 5000µs.

=cut

our $SLEEP = 5000;

=head2 $BASE_SSE_URL

Base URL for tailing SSE logs.

=cut

my $BASE_SSE_URL = '/sse/UserTasks';

# these are mandatory data
my $SCHEMA = {
    'subsystem' => 'string',
    'action'    => 'string',
    'args'      => 'table',
    'exclusive' => 'string',    # only run one task of that type at the same time
};

=head1 METHODS

=head2 Cpanel::UserTasks-E<gt>new()

Create a new UserTasks object.

=cut

sub new ($class) {
    return bless(
        $class->SUPER::new(
            'path'   => Cpanel::UserTasksCore::Utils::queue_dir(),
            'schema' => $SCHEMA
        ),
        $class
    );
}

=head2 $ut-E<gt>add()

Add a task to the UserTasks queue.

Wraps the L<Directory::Queue::Normal::add> method to include starting
up the queue runner program.

=cut

sub add ( $self, %opts ) {

    $opts{exclusive} //= 0;    # disabled by default

    my $result = $self->SUPER::add(%opts);

    $self->_start_queue_runner();

    return $result;
}

=head2 $ut-E<gt>get()

Retrieve the contents of a task.

=head3 Arguments

=over 4

=item $id

An ID value of an element in the queue.

=back

=head3 Returns

A hashref of the contents of the task.  These should be identical to
the arguments which were provided when the task was added to the
queue.

=head3 Dies

If the lock for the entry can not be acquired within $MAX_SLEEP µs,
the function will die.

=head3 Notes

C<Directory::Queue::Normal> requires locking before the contents of a
task can be retrieved; this function rolls these operations together.
C<Cpanel::UserTasks::get> will try the lock several times, sleeping
for $SLEEP µs between each attempt, up to a total of $MAX_SLEEP µs.

=cut

sub get ( $self, $id ) {

    my $locked = $self->_acquire_lock($id) or die "could not get $id";

    my $data = $self->SUPER::get($id);
    $self->unlock($id);

    if ( exists $data->{'args'} && $data->{'args'}{'log_file'} ) {
        $data->{'sse_url'} = $self->get_sse_url( $id, $data->{'args'}{'log_file'} );
    }

    return Cpanel::UserTasksCore::Task->adopt($data);
}

=head2 $ut-E<gt>remove()

Remove a task from the queue.

=head3 Arguments

=over 4

=item $id

An ID value of an element in the queue.

=back

=head3 Dies

If the lock for the entry can not be acquired within $MAX_SLEEP µs,
the function will die.

=head3 Notes

Similarly with the C<get> method, C<Directory::Queue::Normal> requires
locking before a task can be removed; this function rolls these
operations together.  C<Cpanel::UserTasks::remove> will try the lock
several times, sleeping for $SLEEP µs between each attempt, up to a
total of $MAX_SLEEP µs.

=cut

sub remove ( $self, $id ) {

    my $locked = $self->_acquire_lock($id) or die "could not remove $id";
    $self->SUPER::remove($id);

    return;
}

sub _acquire_lock ( $self, $id ) {

    my $total_sleep = 0;
    my $locked      = $self->lock($id);

    while ( !$locked && $total_sleep < $MAX_SLEEP ) {
        Time::HiRes::usleep($SLEEP);
        $total_sleep += $SLEEP;
        $locked = $self->lock($id);
    }

    return $locked;
}

=head1 PRIVATE METHODS

=head2 $ut-E<gt>_start_queue_runner()

Start up the queue running program.  The program itself will worry
about whether another program is running; we'll just start it up.

=cut

sub _start_queue_runner ($self) {

    my $pid = fork;
    return unless defined $pid;
    if ( $pid == 0 ) {
        if ( fork == 0 ) {
            setpgrp( 0, 0 );
            exec('/usr/local/cpanel/bin/process_user_tasks');
            exit 1;
        }
        exit 0;
    }
    waitpid( $pid, 0 );

    return;
}

=head2 $ut-E<gt>get_sse_url()

This function returns the url for using SSE to tail the log for
a user task.

=cut

sub get_sse_url {
    my ( $self, $task_id, $log_file ) = @_;

    require File::Basename;
    $task_id =~ s{/+}{_}g;
    $log_file = File::Basename::basename($log_file);

    return $BASE_SSE_URL . '/' . $task_id . '/' . $log_file;
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::PwCache> and L<Directory::Queue::Normal>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
