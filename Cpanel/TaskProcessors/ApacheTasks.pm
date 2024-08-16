package Cpanel::TaskProcessors::ApacheTasks;

# cpanel - Cpanel/TaskProcessors/ApacheTasks.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache ();

sub skip {
    return 1 unless Cpanel::ConfigFiles::Apache->is_installed();
    return;
}

{

    package Cpanel::TaskProcessors::ApacheTasks::DoVhost;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Try::Tiny;

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 2;
        my ( $user, $domain ) = $task->args();
        require Cpanel::AcctUtils::Account;
        return 0 if !Cpanel::AcctUtils::Account::accountexists($user);
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ( $user, $domain ) = $task->args();

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::ConfigFiles::Apache::VhostUpdate;

        try {
            my ( $result, $message ) = Cpanel::ConfigFiles::Apache::VhostUpdate::do_vhost( $domain, $user );
            die "$message\n" unless $result;
        }
        catch {
            $logger->warn("Failed to add the vhost for ‘$user’: $_");
        };

        return;
    }
}

{

    package Cpanel::TaskProcessors::UpdateUsersJail;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs <= 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::JailManager::Update;
        Cpanel::JailManager::Update::update_users_jail($user);

        return;
    }
}

{

    package Cpanel::TaskProcessors::UpdateUsersVhosts;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs  = scalar $task->args();
        my $is_valid = ( $numargs == 1 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::ConfigFiles::Apache::vhost;
        my ( $ok, $msg ) = Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);
        die "$msg\n" if !$ok;
        require Cpanel::HttpUtils::ApRestart::BgSafe;
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::UpdateOrCreateUsersVhosts;
    use parent -norequire, 'Cpanel::TaskProcessors::UpdateUsersVhosts';

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::ConfigFiles::Apache::vhost;
        my ( $ok, $msg ) = Cpanel::ConfigFiles::Apache::vhost::update_or_create_users_vhosts($user);
        die "$msg\n" if !$ok;
        require Cpanel::HttpUtils::ApRestart::BgSafe;
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        return;
    }

}

{

    package Cpanel::TaskProcessors::ApacheRestart;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return   if $new->command() ne $old->command();
        return 1 if $new->args() && ( $new->args() )[0] eq '--force';
        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        return 1 if 0 == @args;
        return   if 1 != @args;

        return $args[0] eq '--force';
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my $force = scalar $task->args();

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::HttpUtils::ApRestart;
        my ( $status, $message );
        if ($force) {
            ( $status, $message ) = Cpanel::HttpUtils::ApRestart::forced_restart();
        }
        else {
            ( $status, $message ) = Cpanel::HttpUtils::ApRestart::safeaprestart();
        }
        $logger->warn($message) if !$status;

        return 1;
    }

    sub deferral_tags {
        return qw/httpd/;
    }

    sub is_task_deferred {
        my ( $self, $task, $defer_hash ) = @_;

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        return 1 if $self->SUPER::is_task_deferred( $task, $defer_hash );

        require Cpanel::HttpUtils::ApRestart::Defer;
        return 1 if Cpanel::HttpUtils::ApRestart::Defer::is_deferred();

        return Cpanel::TaskProcessors::ApacheTasks::_is_task_deferred_by_httpd_deferred_restart_time();
    }
}

sub _is_task_deferred_by_httpd_deferred_restart_time {
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    if ( $cpconf->{httpd_deferred_restart_time} ) {
        require Cpanel::ConfigFiles::Apache;
        my $pidtime = ( stat Cpanel::ConfigFiles::Apache::apache_paths_facade()->dir_run() . '/httpd.pid' )[9];
        return   if !$pidtime;
        return 1 if $pidtime + $cpconf->{httpd_deferred_restart_time} > time();
    }

    return;
}

{

    package Cpanel::TaskProcessors::ApacheBuildConf;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return 0 == $task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        require Cpanel::ApacheConf::Rebuild;
        require Cpanel::ConfigFiles::Apache;
        return Cpanel::ApacheConf::Rebuild::rebuild_full_http_conf( Cpanel::ConfigFiles::Apache->new()->file_conf() );
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

{

    package Cpanel::TaskProcessors::UserDataUpdate;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return 0 == $task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        return if Cpanel::TaskProcessors::ApacheTasks::skip();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'userdata_update script',
                'cmd'    => '/usr/local/cpanel/bin/userdata_update',
            }
        );
        return;
    }

    sub deferral_tags {
        return qw/httpd/;
    }
}

sub to_register {
    return (
        [ 'apache_restart',                Cpanel::TaskProcessors::ApacheRestart->new() ],
        [ 'build_apache_conf',             Cpanel::TaskProcessors::ApacheBuildConf->new() ],
        [ 'update_users_vhosts',           Cpanel::TaskProcessors::UpdateUsersVhosts->new() ],
        [ 'update_or_create_users_vhosts', Cpanel::TaskProcessors::UpdateOrCreateUsersVhosts->new() ],
        [ 'update_users_jail',             Cpanel::TaskProcessors::UpdateUsersJail->new() ],
        [ 'do_vhost',                      Cpanel::TaskProcessors::ApacheTasks::DoVhost->new() ],
        [ 'userdata_update',               Cpanel::TaskProcessors::UserDataUpdate->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::ApacheTasks - Task processor for restarting Apache

=head1 VERSION

This document describes Cpanel::TaskProcessors::ApacheTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::ApacheTasks;

=head1 DESCRIPTION

Implement the code for the I<apache_restart> and I<build_apache_conf> Tasks. These
are not intended to be used directly.

=head1 INTERFACE

This module defines two subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::ApacheTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::ApacheRestart

This class implements the I<apache_restart> Task. Executes the same code as the
F<safeapacherestart> script to restart Apache. Implemented methods are:

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

=head2 Cpanel::TaskProcessors::ApacheBuildConf

Rebuilds the Apache configuration by launching the C<build_apache_conf> script.
Implements the following methods:

=over 4

=item $proc->overrides( $new, $old )

Returns true if C<$new> is a duplicate of C<$old>.

=back

=head1 DIAGNOSTICS

=over

=item C<< Apache Restart Error: %s >>

If the restart fails, the error message is logged as a warning along with the
actual message.

=back

=head2 Cpanel::TaskProcessors::BuildUserData

Rebuilds the cPanel user data cache configuration by launching the C<userdata_update> script.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::ApacheTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

L<Cpanel::HttpUtils::ApRestart>.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
