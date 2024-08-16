package Cpanel::TaskProcessors::SystemTasks;

# cpanel - Cpanel/TaskProcessors/SystemTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::CacheRebootStatus;

    use parent 'Cpanel::TaskQueue::FastSpawn';
    use Cpanel::LoadModule ();

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub get_child_timeout {
        Cpanel::LoadModule::load_perl_module('Cpanel::Serverinfo::CachedRebootStatus');

        # Prevent this refresh from running more than X - 0.5 minutes, because
        # after X minutes, the lock will be broken and a rename() could drop an
        # incomplete JSON file onto the system, causing errors.
        return Cpanel::Serverinfo::CachedRebootStatus::UPDATE_TIMEOUT() - 30;
    }

    sub _do_child_task {
        Cpanel::LoadModule::load_perl_module('Cpanel::Serverinfo::CachedRebootStatus');
        return Cpanel::Serverinfo::CachedRebootStatus::_update_cache_file();
    }

    sub _do_timeout {
        Cpanel::LoadModule::load_perl_module('Cpanel::Serverinfo::CachedRebootStatus');
        return Cpanel::Serverinfo::CachedRebootStatus::_abort_cache_file_update();
    }
}

sub to_register {
    return (
        [ 'recache_system_reboot_data', Cpanel::TaskProcessors::CacheRebootStatus->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::SystemTasks - Task processor for system tasks

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::SystemTasks;

=head1 DESCRIPTION

Implement the code for the C<recache_system_reboot_data> task. This is not
intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a
package method.

=head2 Cpanel::TaskProcessors::SystemTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.

=cut
