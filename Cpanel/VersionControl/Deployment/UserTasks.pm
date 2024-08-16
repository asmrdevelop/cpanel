package Cpanel::VersionControl::Deployment::UserTasks;

# cpanel - Cpanel/VersionControl/Deployment/UserTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::Deployment::UserTasks

=head1 SYNOPSIS

    use Cpanel::VersionControl::Deployment::UserTasks;

    my $ut = Cpanel::VersionControl::Deployment::UserTasks->new();

    my $task_id = $ut->add(
        'subsystem' => 'VersionControl',
        'action'    => 'deploy',
        'args'      => {
            'repository_root' => '/some/repository/path',
            'log_file'        => '/some/log/file/path'
        }
    );

    my $contents = $ut->get($task_id);

    $ut->remove($task_id);

=head1 DESCRIPTION

C<Cpanel::VersionControl::Deployment::UserTasks> is a subclass of the
C<Cpanel::UserTasks> user-facing task queue.  The existing UserTasks
implementation does not provide a facility for any activities which
require the task ID, but must be performed before the task queue
runner program starts.

This subclass overrides only the C<add()> method, in order to insert a
database record for each deployment action, before starting up the
queue runner.

=cut

use cPstrict;

use parent 'Cpanel::UserTasks';

use Cpanel::VersionControl::Deployment::DB ();
use Directory::Queue::Normal               ();

=head1 METHODS

=head2 $ut-E<gt>add()

Add a task to the UserTasks queue.

Wraps the L<Directory::Queue::Normal::add> method to include adding
records to the deployment database and starting up the queue runner
program.

=cut

sub add ( $self, @args ) {

    my $id   = $self->SUPER::add(@args);
    my $task = $self->get($id);

    my $result = Cpanel::VersionControl::Deployment::DB->new()->queue(
        $id,
        $task->{'args'}{'repository_root'},
        $task->{'args'}{'log_file'}
    );

    return $result;
}

1;
