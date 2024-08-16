package Cpanel::TaskProcessors::WPTK;

# cpanel - Cpanel/TaskProcessors/WPTK.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

{

    package Cpanel::TaskProcessors::WPTK::InstallOnDomain;

    use parent qw(
      Cpanel::TaskQueue::FastSpawn
    );

    use Cpanel::Binaries ();

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $user, $domain, $email ) = $task->args();
        die "Both user and domain are required." unless $user && $domain;

        my $cmd = Cpanel::Binaries::path('wp-toolkit');

        my @args = ('--install');

        push @args, '-domain-name', $domain;
        push @args, '-username',    $user;
        push @args, '-admin-email', $email if $email;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'wordpress_install_on_domain',
                'cmd'    => $cmd,
                'args'   => \@args
            }
        );

        return;
    }
}

sub to_register {
    return (
        [ 'wordpress_install_on_domain' => Cpanel::TaskProcessors::WPTK::InstallOnDomain->new() ],
        [ 'install_wptk'                => Cpanel::TaskProcessors::WPTK::initial_install_wptk->new() ],
    );
}

{
    # This is for initial cpanel installs only.

    package Cpanel::TaskProcessors::WPTK::initial_install_wptk;
    use parent 'Cpanel::TaskQueue::FastSpawn';
    use Cpanel::Pkgr ();
    use Whostmgr::PleskWordPressToolkit;

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

=head1 TOUCH FILES

This task processor respects the /var/cpanel/nowptoolkit touch file, which is
created by the installer if --skip-wptoolkit is passed. If this task processor
is ever used for manual installs chosen by the system administrator, you will
need to add something that either deletes the touch file before queueing the
task or causes the task processor to ignore it in those cases.

=cut

        if ( -e Whostmgr::PleskWordPressToolkit::DISABLE_TOUCH_FILE() ) {
            $logger->info('WP Toolkit installation was disabled on this system.');
            return;
        }

        $logger->info('Installing WP Toolkit.');

        # Once the logger is destroyed, lock_for_external_install will unlock the distro packaging system
        # Uses queueprocd.log when called by queueprocd.  Some 3rd party plugins use their own, see ImunifyAV.pm.
        my $lock_released_on_destroy = Cpanel::Pkgr::lock_for_external_install($logger);

        if ( Whostmgr::PleskWordPressToolkit::install() ) {
            $logger->info('WP Toolkit installation succeeded.');
        }
        else {
            $logger->info('WP Toolkit installation failed.');
        }

        return;
    }

    sub deferral_tags {
        return qw{rpm run_base_package_update run_system_package_update};
    }
}
1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::WPTK - Task processor for WP Toolkit activities.

=head1 VERSION

This document describes Cpanel::TaskProcessors::WPTK

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::WPTK;

    # Installs WP Toolkit via a task queue file
    Cpanel::ServerTasks::queue_task( ['WPTK'], 'install_wptk' );

    # updates the license via a task queue file
    Cpanel::ServerTasks::queue_task( ['WPTK'], 'update_wptk' );

    # retry updates the license via a task queue file
    use constant WAIT_DELAY => 60; # 1 min delay
    Cpanel::ServerTasks::schedule_task( ['WPTK'], WAIT_DELAY, 'update_wptk_retry' );

=head1 DESCRIPTION

Provides methods to background running an install of WPTK or an update of the WPTK license.

=head1 INTERFACE

This module defines several subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::WPTK::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::WPTK::install_wptk

Install WP Toolkit in the background. This is intended for new cPanel installs.

=head2 Cpanel::TaskProcessors::WPTK::update_wptk

Run the license update script in the background. Use this processor only on the first attempt.

=head2 Cpanel::TaskProcessors::WPTK::update_wptk_retry

Run the license update script in the background. Use this processor only on additional attempts after the first attempt.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.
