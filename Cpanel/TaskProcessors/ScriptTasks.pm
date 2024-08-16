package Cpanel::TaskProcessors::ScriptTasks;

# cpanel - Cpanel/TaskProcessors/ScriptTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::ScriptTasks

=head1 DESCRIPTION

This module exposes the following tasks:

=over

=item * C<run_script> - Run a script with given arguments. This is
similar to running in the background, but the advantage is that if you
have 1,000 scripts, the task runner will execute them subject to its
limit of concurrent processes. That way you avoid excessive load on the
server.

Bear in mind the following prior to calling this task:

=over

=item * This task is B<NOT> deduplicated. If you enqueue the same
script, even with the same arguments, 3 times, then it’ll run 3 times.
(If there’s need for a deduplicated variant of this, it’ll be easy
to implement.)

=item * This task always has a fork/exec overhead. You can avoid that
overhead by creating a dedicated task for your logic rather than calling
this task. Obviously that entails a maintenance overhead, though, that
may or may not outweigh the performance gain of a dedicated task.
In general, though, for a task that runs in the background the
fork/exec overhead is probably of little consequence.

=back

=back

=cut

{

    package Cpanel::TaskProcessors::ScriptTasks::RunScript;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return scalar $task->args() > 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $cmd, @args ) = $task->args();

        $self->checked_system(
            {
                logger => $logger,
                cmd    => $cmd,
                args   => \@args,
            }
        );

        return;
    }
}

sub to_register {
    return (
        [ 'run_script', Cpanel::TaskProcessors::ScriptTasks::RunScript->new() ],
    );
}

1;
