package Cpanel::TaskProcessors::PHPFPMTasks;

# cpanel - Cpanel/TaskProcessors/PHPFPMTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::EnsureFPMOnBoot;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs == 0 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($user) = $task->args();

        require Cpanel::PHPFPM::Tasks;

        $logger->info("PHPFPM: ensure_fpm_on_boot executing");
        Cpanel::PHPFPM::Tasks::ensure_all_fpm_versions_start_on_reboot();
        $logger->info("PHPFPM: ensure_fpm_on_boot completed");

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/ensure_fpm_on_boot httpd/;
    }

    package Cpanel::TaskProcessors::EnablePHPFPM;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs == 0 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $logger->info("PHPFPM: enable_fpm executing");

        require Cpanel::PHPFPM::ConvertAll;
        require Cpanel::PHPFPM::Tasks;
        require Cpanel::PHPFPM::EnableQueue::Harvester;
        require Cpanel::PHPFPM::RebuildQueue::Adder;

        try {
            my @domains_to_enable;
            Cpanel::PHPFPM::EnableQueue::Harvester->harvest( sub { push @domains_to_enable, shift } );
            foreach my $domain (@domains_to_enable) {
                try {
                    $logger->info("Enabling Domain: $domain");
                    Cpanel::PHPFPM::ConvertAll::convert_user_domain( $logger, $domain, 0 );
                    Cpanel::PHPFPM::RebuildQueue::Adder->add($domain);
                }
                catch {
                    $logger->info("Failed to process Domain: $domain");
                }
            }

            # Chain the rebuild as a secondary queued task --
            # otherwise the rebuild which is *already queued* by creating accounts will cause double restarts
            require Cpanel::ServerTasks;
            Cpanel::ServerTasks::queue_task( ['PHPFPMTasks'], "rebuild_fpm" );
        }
        catch {
            $logger->info("Failed Reason: $_");
        };

        $logger->info("PHPFPM: enable_fpm completed");

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/enable_fpm/;
    }

    package Cpanel::TaskProcessors::RebuildPHPFPM;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs == 0 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ($domain) = $task->args();

        $logger->info("PHPFPM: rebuild executing");

        require Cpanel::PHPFPM::Tasks;

        try {
            Cpanel::PHPFPM::Tasks::perform_rebuilds();
        }
        catch {
            $logger->info("Failed to Rebuild Reason: $_");
        };

        # Only queue apache restart, as Cpanel::PHPFPM::Tasks::perform_rebuilds will restart apache_php_fpm
        # via the logic in Cpanel::PHPFPM::rebuild_files (as $do_restart is a default of YES in this scenario).
        require Cpanel::HttpUtils::ApRestart::BgSafe;
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        $logger->info("PHPFPM: rebuild_fpm completed");

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/rebuild_fpm httpd/;
    }

}

sub to_register {
    return (
        [ 'ensure_fpm_on_boot', Cpanel::TaskProcessors::EnsureFPMOnBoot->new() ],
        [ 'enable_fpm',         Cpanel::TaskProcessors::EnablePHPFPM->new() ],
        [ 'rebuild_fpm',        Cpanel::TaskProcessors::RebuildPHPFPM->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::PHPFPMTasks - Task processor for PHPFPM

=head1 VERSION

This document describes Cpanel::TaskProcessors::PHPFPM

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::PHPFPMTasks;

=head1 DESCRIPTION

Implement the code for the I<ensure_fpm_on_boot> Tasks. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::PHPFPMTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::EnsureFPMOnBoot

This class implements the I<ensure_fpm_on_boot> Task.

=head2 Cpanel::TaskProcessors::EnablePHPFPM

This class implements the I<enable_fpm> Task.

=head2 Cpanel::TaskProcessors::RebuildPHPFPM

This class implements the I<rebuild_fpm> Task.

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

If the new task has the same command and the I<--force> argument, it overrides
the old task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if the task has no arguments or only the C<--force> argument.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::PHPFPMTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

L<Cpanel::PHPFPM::Tasks>.
L<Cpanel::PHPFPM::ConvertAll>.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.
