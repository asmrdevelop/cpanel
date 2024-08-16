package Cpanel::TaskProcessors::ImunifyTasks;

# cpanel - Cpanel/TaskProcessors/ImunifyTasks.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::TaskProcessors::ImunifyTasks

=head1 DESCRIPTION

Task processor for the installation of ImunifyAV. This module may also be
used for any other Imunify-related background tasks that need to be performed.

=cut

{

    package Cpanel::TaskProcessors::ImunifyTasks::InstallImunifyAV;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args;
    }

    sub deferral_tags {
        return qw(rpm);
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Whostmgr::Store::Product::ImunifyAV;
        my $product = Whostmgr::Store::Product::ImunifyAV->new(
            'redirect_path' => '/',
            'wait'          => 1,     # Whostmgr::Store has its own background mechanism, but we want taskqueue to handle this instead so we can use deferral tags and a delay
        );

        if ( !$product->should_offer ) {
            $logger->info('ImunifyAV is not offered for this platform; skipping installation.');
            return;
        }

=head1 TOUCH FILES

This task processor respects the /var/cpanel/noimunifyav touch file, which is
created by the installer if --skip-imunifyav is passed. If this task processor
is ever used for manual installs chosen by the system administrator, you will
need to add something that either deletes the touch file before queueing the
task or causes the task processor to ignore it in those cases.

=cut

        if ( -e Whostmgr::Store::Product::ImunifyAV::DISABLE_TOUCH_FILE() ) {
            $logger->info('ImunifyAV installation was disabled on this system.');
            return;
        }

        $logger->info('Installing ImunifyAV (free version) …');

        my ( $status, $reason ) = eval { $product->ensure_installed() };
        my $exception = $@;

        if ($status) {
            $logger->info('ImunifyAV installation succeeded.');
        }
        else {
            $logger->info( sprintf( 'ImunifyAV installation failed: %s', $exception || $reason ) );
            $logger->info('See /var/log/imav-deploy.log or /var/cpanel/imunifyav-install.log for more information.');
        }

        return;
    }
}

{

    package Cpanel::TaskProcessors::ImunifyTasks::InstallImunify360;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args;
    }

    sub deferral_tags {
        return qw(rpm);
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Whostmgr::Imunify360;
        my $product = Whostmgr::Imunify360->new( 'redirect_path' => '/', 'wait' => 1 );

        $logger->info('Installing Imunify 360 …');

        my $status    = eval { $product->install_implementation() };
        my $exception = $@;

        if ($status) {
            $logger->info('Imunify 360 installation succeeded.');
        }
        else {
            $logger->info( sprintf( 'Imunify 360 installation failed: %s', $exception || 'unknown reason' ) );
            $logger->info('See /var/cpanel/logs/imunify360-install.log for more information.');
        }

        return;
    }
}

=head1 FUNCTIONS

=head2 to_register() - Do not call this directly

Register the handlers.

=cut

sub to_register {
    return (
        [ 'install_imunifyav',  Cpanel::TaskProcessors::ImunifyTasks::InstallImunifyAV->new() ],
        [ 'install_imunify360', Cpanel::TaskProcessors::ImunifyTasks::InstallImunify360->new() ],
    );
}

1;
