package Cpanel::TaskProcessors::PHPTasks;

# cpanel - Cpanel/TaskProcessors/PHPTasks.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

{
    # I'm sure this looks repetitive, because it is.
    package Cpanel::TaskProcessors::checkphpini;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args { return !$_[1] ? 1 : !scalar( $_[1]->args() ); }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::SafeRun::Object;

        my $run = Cpanel::SafeRun::Object->new_or_die(
            program => '/usr/local/cpanel/bin/checkphpini',
        );

        return;
    }

}

{

    package Cpanel::TaskProcessors::install_php_inis;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args { return !$_[1] ? 1 : !scalar( $_[1]->args() ); }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::SafeRun::Object;

        my $run = Cpanel::SafeRun::Object->new_or_die(
            program => '/usr/local/cpanel/bin/install_php_inis',
        );

        return;
    }

}

# Turns out that if you want the above two to process in sequence, you are SOL just jamming em into the taskqueue,
# as those jobs execute in *random* order.
{

    package Cpanel::TaskProcessors::checkphpini_and_install_php_inis;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args { return !$_[1] ? 1 : !scalar( $_[1]->args() ); }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::SafeRun::Object;

        my $run_checkphpini = Cpanel::SafeRun::Object->new_or_die(
            program => '/usr/local/cpanel/bin/checkphpini',
        );

        my $run_install_php_inis = Cpanel::SafeRun::Object->new_or_die(
            program => '/usr/local/cpanel/bin/install_php_inis',
        );

        require Cpanel::Services::Enabled;
        if ( Cpanel::Services::Enabled::is_enabled('cpanel_php_fpm') ) {
            require Cpanel::ServerTasks;
            Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 3, "restartsrv cpanel_php_fpm" );
        }

        return;
    }

}

{

    package Cpanel::TaskProcessors::rebuild_cpanel_php_fpm_pool_configs;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args { return !$_[1] ? 1 : !scalar( $_[1]->args() ); }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        require Cpanel::Services::Enabled;
        if ( Cpanel::Services::Enabled::is_enabled('cpanel_php_fpm') ) {
            require Cpanel::Server::FPM::Manager;
            Cpanel::Server::FPM::Manager::sync_config_files();
        }
        return;
    }

}

sub to_register {
    return (
        [ 'checkphpini',                         Cpanel::TaskProcessors::checkphpini->new() ],
        [ 'install_php_inis',                    Cpanel::TaskProcessors::install_php_inis->new() ],
        [ 'checkphpini_and_install_php_inis',    Cpanel::TaskProcessors::checkphpini_and_install_php_inis->new() ],
        [ 'rebuild_cpanel_php_fpm_pool_configs', Cpanel::TaskProcessors::rebuild_cpanel_php_fpm_pool_configs->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::PHPTasks - Task processor for running some php ini mongling scripts.

=head1 VERSION

This document describes Cpanel::TaskProcessors::PHPTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::PHPTasks;

=head1 DESCRIPTION

Implement the code for the I<checkphpini> and I<install_php_inis> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::PHPTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::checkphpini

This class implements the I<checkphpini> Task. Implemented methods are:

=over 4

=item $proc->is_valid_args( $task )

Returns !scalar($task->args()), as no args are valid

=back

=head2 Cpanel::TaskProcessors::install_php_inis

This class implements the I<install_php_inis> Task. Implemented methods are:

=over 4

=item $proc->is_valid_args( $task )

Returns !scalar($task->args()), as no args are valid

=back

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

???

=head1 AUTHOR

Thomas A. Baugh  C<< thomas.baugh@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, L.L.C All rights reserved.
