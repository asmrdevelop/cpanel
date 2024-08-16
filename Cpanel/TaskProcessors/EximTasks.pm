package Cpanel::TaskProcessors::EximTasks;

# cpanel - Cpanel/TaskProcessors/EximTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::EximBuildConf;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return if $new->command() ne $old->command();
        my @args = $new->args();
        return 1 if @args == 1 && $args[0] eq '--restart';
        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();
        return 1 if @args == 1 && $args[0] eq '--restart';
        return 1 if @args == 0;
        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @args    = $task->args();
        my $restart = grep { $_ eq '--restart' } @args;

        # Optimizing this by requiring buildeximconf in the same process
        # instead of executing it in a subprocess results in the remainder of
        # this task not executing because it calls exit. Should be safe to
        # optimize after buildeximconf is converted into a modulino.
        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'buildeximconf script',
                'cmd'    => '/usr/local/cpanel/scripts/buildeximconf',
            }
        );

        if ($restart) {
            require Cpanel::ServerTasks;
            Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], 'restartsrv exim' );
        }

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/exim/;
    }
}

{

    package Cpanel::TaskProcessors::BuildRemoteMXCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    *overrides = __PACKAGE__->can('is_dupe');

    use constant deferral_tags => qw/exim/;

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return 0 == $task->args();
    }

    sub _do_child_task {
        my ($self) = @_;

        require AnyEvent;
        require Cpanel::Exim::RemoteMX::Create;
        require Cpanel::DNS::Unbound::Async;

        my $dns = Cpanel::DNS::Unbound::Async->new();

        my $cv = AnyEvent->condvar();

        Cpanel::Exim::RemoteMX::Create::create_domain_remote_mx_ips_file($dns)->then($cv);

        $cv->recv();

        return;
    }
}

sub to_register {
    return (
        [ 'buildeximconf',         Cpanel::TaskProcessors::EximBuildConf->new() ],
        [ 'build_remote_mx_cache', Cpanel::TaskProcessors::BuildRemoteMXCache->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::EximTasks - Task processor for handling Exim-related
tasks.

=head1 SYNOPSIS

    # processor side
    use Cpanel::TaskQueue;
    my $queue = Cpanel::TaskQueue->new(
        {
            name      => 'servers',
            cache_dir => '/var/cpanel/taskqueue'
        }
    );
    Cpanel::TaskQueue->register_task_processor(
        'EximTasks',
        Cpanel::TaskProcessors::EximTasks->new()
    );

    # client/queuing side
    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['EximTasks'],
        'buildeximconf --restart'
    );
    Cpanel::ServerTasks::queue_task(
        ['EximTasks'],
        'build_remote_mx_cache'
    );

=head1 DESCRIPTION

A task processor that handles various background tasks related to Exim, such
as rebuilding the configuration or cache files.

=head1 TASKS

=head2 to_register

Register the following tasks:

=over 4

=item buildeximconf

Rebuild the Exim configuration files and optionally queue a restart for the
Exim service.

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['EximTasks'],
        'buildeximconf --restart'
    );

This task takes one optional argument C<--restart> if the service needs
to be restarted after the configuration update. This option is preferable
over using a separate service restart task because it ensures the
configuration is updated before restarting the service, and separate tasks
currently can NOT guarantee correct ordering.

This task is deduplicated and providing the C<--restart> argument overrides
existing buildeximconf tasks with or without the option.

=item build_remote_mx_cache

Rebuild the remote MX IP address cache.

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['EximTasks'],
        'build_remote_mx_cache'
    );


This task is deduplicated.

=back
