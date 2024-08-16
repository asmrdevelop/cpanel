package Cpanel::TaskProcessors::PluginTasks;

# cpanel - Cpanel/TaskProcessors/PluginTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::PluginTasks::Install;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;
    use Cpanel::LoadModule ();

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($plugin) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::Plugins');
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        try {
            Cpanel::Plugins::install_plugins($plugin);
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        return 1;
    }
}
{

    package Cpanel::TaskProcessors::PluginTasks::Uninstall;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;
    use Cpanel::LoadModule ();

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($plugin) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::Plugins');
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        try {
            Cpanel::Plugins::uninstall_plugins($plugin);
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        return 1;
    }
}

sub to_register {
    return (
        [ 'install_plugin',   Cpanel::TaskProcessors::PluginTasks::Install->new() ],
        [ 'uninstall_plugin', Cpanel::TaskProcessors::PluginTasks::Uninstall->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::PluginTasks - Task processor for Plugin

=head1 VERSION

This document describes Cpanel::TaskProcessors::PluginTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::PluginTasks;

=head1 DESCRIPTION

Implement the code for the I<write_gemrc> task. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::PluginTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::PluginTasks::Install

This class install a plugin

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if a plugin name is passed.

=back

=head2 Cpanel::TaskProcessors::PluginTasks::Uninstall

This class uninstalls a plugin

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if a plugin name is passed.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::PluginTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.
