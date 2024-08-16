package Cpanel::TaskProcessors::cPAddons;

# cpanel - Cpanel/TaskProcessors/cPAddons.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 TASK PROCESSOR FOR CPADDONS TASKS

Any TaskQueue tasks related to cPAddons can go in this module.

=cut

{

    package Cpanel::TaskProcessors::cPAddons::RebuildAvailableAddonsPackagesCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args;
    }

    sub deferral_tags {
        return qw(cpaddons);
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'rebuild_available_addons_packages_cache',
                'cmd'    => '/usr/local/cpanel/scripts/rebuild_available_addons_packages_cache',
                'args'   => [],
            }
        );

        return;
    }

}

{

    package Cpanel::TaskProcessors::cPAddons::Install;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'install_cpaddons',
                'cmd'    => '/usr/local/cpanel/bin/install_cpaddons',
            }
        );
        return;
    }

}

=head2 to_register

Currently registers these tasks:

rebuild_available_addons_packages_cache - Rebuilds /var/cpanel/available_addons_packages.cache

install_cpaddons - Runs /usr/local/cpanel/bin/install_cpaddons

=cut

sub to_register {
    return (
        # need to preserve the original name for backward compatibility
        [ 'rebuild_available_rpm_addons_cache',      Cpanel::TaskProcessors::cPAddons::RebuildAvailableAddonsPackagesCache->new() ],
        [ 'rebuild_available_addons_packages_cache', Cpanel::TaskProcessors::cPAddons::RebuildAvailableAddonsPackagesCache->new() ],
        [ 'install_cpaddons',                        Cpanel::TaskProcessors::cPAddons::Install->new() ],
    );
}

1;
