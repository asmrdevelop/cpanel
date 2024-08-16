package Cpanel::TaskProcessors::MaintenanceTasks;

# cpanel - Cpanel/TaskProcessors/MaintenanceTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::MaintenanceTasks::SystemUpdate;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'update-packages',
                'cmd'    => '/usr/local/cpanel/scripts/update-packages',
            }
        );
        return;
    }

    sub deferral_tags {
        return qw{run_system_package_update};
    }

}

{

    package Cpanel::TaskProcessors::MaintenanceTasks::BasePackageUpdate;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        require Cpanel::Sysup;
        Cpanel::Sysup->new()->run() or die "Failed to call Cpanel::Sysup::run()";
        return;
    }

    sub deferral_tags {
        return qw{run_base_package_update};
    }

}

{

    package Cpanel::TaskProcessors::MaintenanceTasks::ForceUpdateCageFS;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::CloudLinux::CageFS;
        Cpanel::CloudLinux::CageFS::force_cagefs_update();

        return;
    }
}

{

    package Cpanel::TaskProcessors::MaintenanceTasks::UninstallCpanelMonitoringPackages;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub deferral_tags {
        return qw{run_base_package_update run_system_package_update};
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $logger->info(q{Uninstalling the monitoring agent plugins.});

        require Cpanel::Plugins;
        eval { Cpanel::Plugins::uninstall_plugins( 'cpanel-monitoring-agent', 'cpanel-monitoring-whm-plugin', 'cpanel-monitoring-cpanel-plugin' ); };
        $logger->warn($@) if $@;

        return;
    }
}

sub to_register {
    return (
        [ 'run_base_package_update',              Cpanel::TaskProcessors::MaintenanceTasks::BasePackageUpdate->new() ],
        [ 'run_system_package_update',            Cpanel::TaskProcessors::MaintenanceTasks::SystemUpdate->new() ],
        [ 'force_update_cagefs',                  Cpanel::TaskProcessors::MaintenanceTasks::ForceUpdateCageFS->new() ],
        [ 'uninstall_cpanel_monitoring_packages', Cpanel::TaskProcessors::MaintenanceTasks::UninstallCpanelMonitoringPackages->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::MaintenanceTasks - Task processor for running some Maintenance Account maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::MaintenanceTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::MaintenanceTasks;

=head1 DESCRIPTION

Implement the code for the I<run_system_package_update> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::MaintenanceTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::MaintenanceTasks::SystemUpdate

This is a thin wrapper around update-packages (it could be something different in the future)

=head2 Cpanel::TaskProcessors::MaintenanceTasks::UninstallCpanelMonitoringPackages

Uninstall the cPanel Monitoring packages.

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C All rights reserved.
