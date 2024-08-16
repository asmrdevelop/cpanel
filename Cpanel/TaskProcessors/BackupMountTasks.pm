package Cpanel::TaskProcessors::BackupMountTasks;

# cpanel - Cpanel/TaskProcessors/BackupMountTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::BackupMountReleaseLocks;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my @args = $task->args();

        return 1 == @args;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        require Cpanel::BackupMount;
        my $backupmount = $task->get_arg(0);
        return Cpanel::BackupMount::release_mount_lock($backupmount);
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/backup/;
    }
}

sub to_register {
    return ( [ 'release_mount_lock', Cpanel::TaskProcessors::BackupMountReleaseLocks->new() ] );
}

1;
