package Cpanel::ServerTasks;

# cpanel - Cpanel/ServerTasks.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::TaskQueue::Loader ();

use Try::Tiny;

our $VERSION = '0.0.7';

my $logger;
my $qname = 'servers';
my $queue;
my $sched;

#overridden in tests
our $queue_dir = '/var/cpanel/taskqueue';

# utf-8 roundtrip safe when used with Cpanel::TaskQueue::Serializer::decode_param method.
sub encode_param {
    my $reference = shift;
    require Cpanel::AdminBin::Serializer;
    require Cpanel::Encoder::URI;
    my $json           = Cpanel::AdminBin::Serializer::Dump($reference);
    my $encoded_string = Cpanel::Encoder::URI::uri_encode_str($json);
    return $encoded_string;
}

sub queue_task ( $plugins, @cmds ) {

    queue_tasks_and_get_ids( $plugins, @cmds );

    return 1;
}

sub queue_single_task_and_get_id ( $plugins, $task ) {

    my $ids = queue_tasks_and_get_ids( $plugins, $task ) // [];

    return $ids->[0];
}

sub queue_tasks_and_get_ids ( $plugins, @cmds ) {
    if ( ref $plugins ne 'ARRAY' ) {
        die "Implementor Error: queue_task requires a list of plugins to load as the first argument";
    }
    if ( !@cmds ) {
        die "Implementor Error: queue_task requires a list of tasks to queue";
    }
    _init_task_queue_and_plugins($plugins);

    $logger ||= Cpanel::LoggerAdapter::Lazy->new();
    $queue  ||= Cpanel::TaskQueue->new( { name => $qname, cache_dir => $queue_dir, logger => $logger } );    # PPI USE OK -- This is loaded by Cpanel::TaskQueue::Loader

    my @ids;
    $queue->do_under_guard( sub { @ids = $_[0]->queue_tasks(@cmds) } );

    return \@ids;
}

#
# As of v60 schedule_task collapses duplicates
# If you schedule a task in the future and one is already
# in the queue your task will be ignored.  As of v60 this is
# the behavior we want in all current use cases and was likely
# expected by the current callers of this function.
#
sub schedule_task {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $plugins = shift;
    my $delay   = shift;    # seconds
    if ( ref $plugins ne 'ARRAY' ) {
        die "Implementor Error: schedule_task requires a list of plugins to load as the first argument";
    }
    if ( !$delay || $delay !~ m{^[0-9]+$} ) {
        die "Implementor Error: schedule_task requires a numeric delay as the second argument";
    }
    if ( !@_ ) {
        die "Implementor Error: schedule_task requires a list of tasks to schedule";
    }
    return schedule_tasks( $plugins, [ map { [ $_, { 'delay_seconds' => $delay } ] } @_ ] );
}

sub schedule_tasks {
    my ( $plugins, $command_args_ars ) = @_;
    _init_task_queue_and_plugins($plugins);
    if ( ref $command_args_ars ne 'ARRAY' ) {
        die "Implementor Error: schedule_tasks requires an arrayref of commands and taskqueue schedule arguments";
    }

    require Cpanel::TaskQueue::Scheduler::DupeSupport;

    $logger ||= Cpanel::LoggerAdapter::Lazy->new();
    $sched  ||= Cpanel::TaskQueue::Scheduler::DupeSupport->new( { name => $qname, cache_dir => $queue_dir, logger => $logger } );

    my $ret;

    $sched->do_under_guard(
        sub {
            $ret = $_[0]->schedule_tasks($command_args_ars);
        }
    );

    return $ret;
}

sub load_taskqueue_modules {
    if ( !$logger ) {
        require Cpanel::LoggerAdapter::Lazy if !$INC{'Cpanel/LoggerAdapter/Lazy.pm'};
        $logger ||= Cpanel::LoggerAdapter::Lazy->new();
    }
    return Cpanel::TaskQueue::Loader::load_taskqueue_modules($logger);
}

sub _init_task_queue_and_plugins {
    my $plugins = shift;

    load_taskqueue_modules();

    local @INC = ( '/var/cpanel/perl', @INC );

    foreach my $p (@$plugins) {
        my $mod     = index( $p, '::' ) > -1 ? $p : 'Cpanel::TaskProcessors::' . $p;
        my $inc_key = $mod;
        substr( $inc_key, index( $inc_key, '::' ), 2, '/' ) while index( $inc_key, '::' ) > -1;
        next if $INC{"$inc_key.pm"};
        unless ( Cpanel::TaskQueue::PluginManager::load_plugin_by_name($mod) ) {    # PPI USE OK -- This is loaded by Cpanel::TaskQueue::Loader
            die "ERROR: Unable to load plugin: $p ($mod)\n";
        }
    }
    return 1;
}

1;
__END__

=head1 NAME

Cpanel::ServerTasks - Utility methods to simplify queuing server-related tasks.

=head1 VERSION

This document describes Cpanel::ServerTasks version 0.0.4


=head1 SYNOPSIS

    use Cpanel::ServerTasks;

    Cpanel::ServerTasks::queue_task( [ 'ApacheTasks' ], 'buildapacheconf' );

    Cpanel::ServerTasks::schedule_task( [ 'ApacheTasks' ], 60, 'buildapacheconf' );

    Cpanel::ServerTasks::schedule_tasks( ['MysqlTasks'], [ [ 'mysqluserstore', { 'delay_seconds' => 1 } ], [ 'mysqluserstore', { 'delay_seconds' => 2 } ] ] );

=head1 DESCRIPTION

Provide a simpler interface to the TaskQueue for the server queue. Using this interface,
you just need to provide the command string and not be aware of the TaskQueue classes
at all.

=head1 INTERFACE

=head2 Cpanel::ServerTasks::queue_task( $cmdlist )

If the first parameter is an array reference, the values in this list are
treated as the names of plugins. The other parameters in the argument list are
treated as C<cmd strings>. Data structure references may be passed as strings
serialized and encoded via C<Cpanel::ServerTask::encode_param>. Decoding
happens via C<Cpanel::TaskQueue::Serializer::decode_param> in the task. When
used with the latter decode method, the original data is UTF-8 roundtrip safe.
That means UTF-8 will be preserved throughout.

C<queue_task> queues each C<cmd string> as a separate task to run at the next
opportunity. Throws an exception if the command string is not recognized.

Returns a uuid if the task was queued or undef if it was a duplicate command
that was discarded.

=head2 Cpanel::ServerTasks::schedule_task( $delay_in_secs, $cmdlist )

If the first parameter is an array reference, the values in this list are
treated as the names of plugins. The first non-arrayref parameter must be a
number of seconds to delay the queuing of the tasks. The other parameters in
the argument list are treated as C<cmd strings>. C<schedule_task> queues each
C<cmd string> as a separate task to be queued after a minimum of C<$delay>
seconds. Throws an exception if the command string is not recognized.

Returns a uuid if the task was scheduled or undef if it was a duplicate command
that was discarded.

=head2 Cpanel::ServerTasks::schedule_tasks([ TaskQueueModule, ... ], [ ['task',{args... } ], ... ])

Schedule multiple tasks in the queueprocd taskqueue.

=over 3

=item Input

Example:
    Cpanel::ServerTasks::schedule_tasks( ['MysqlTasks'], [ [ 'mysqluserstore', { 'delay_seconds' => 1 } ], [ 'mysqluserstore', { 'delay_seconds' => 2 } ] ] );


=over 3

=item C<ARRAYREF>

    An arrayref of TaskProcesssor modules to load.
    These correspond to the modules in
    /usr/local/cpanel/TaskProcessors

=item C<ARRAYREF> of C<ARRAYREF>s

    An arrayref of tasks to schedule.

    Each tasks has two elements in the
    arrayref.

=over 3

=item The first element is the command

=item The second element is a hashref of arguments

=back

=back

=item Output

A list of uuids corresponding to the tasks that
were scheduled.  Any tasks that fail to schedule
will return undef in the corresponding slot.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::ServerTasks requires no configuration files or environment variables.

=head1 DEPENDENCIES

L<Cpanel::TaskQueue>, L<Cpanel::TaskQueue::Scheduler>, and
L<Cpanel::TaskQueue::PluginManager>.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2010, cPanel, Inc. All rights reserved.
