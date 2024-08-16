package Cpanel::TaskProcessors::MysqlTasks;

# cpanel - Cpanel/TaskProcessors/MysqlTasks.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OS ();

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::MysqlTasks

=head1 DESCRIPTION

Deferred tasks for MySQL and, in some cases, PostgreSQL.

=head1 TASKS

=over

=item C<flushprivs> - MySQL only; runs C<FLUSH PRIVILEGES>

=item C<mysqluserstore> - No longer used, left for backwards compat

=item C<dbstoregrants> - MySQL B<AND> PostgreSQL; runs C<bin/dbstoregrants>
=item C<dbindex> - MySQL B<AND> PostgreSQL; runs C<bin/dbindex>

=back

=cut

{

    package Cpanel::TaskProcessors::MysqlTasks::Flush;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ($self) = @_;

        require Cpanel::MysqlUtils::Connect;
        return Cpanel::MysqlUtils::Connect::get_dbi_handle()->do('FLUSH PRIVILEGES');
    }
}

{

    package Cpanel::TaskProcessors::MysqlTasks::SyncGrantsFromDisk;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ($self) = @_;

        require Cpanel::Mysql::SyncUsers;
        Cpanel::Mysql::SyncUsers::sync_grant_files_to_db();

        return;
    }
}

{

    package Cpanel::TaskProcessors::MysqlUserStore;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ($self) = @_;

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/mysql/;
    }
}

{

    package Cpanel::TaskProcessors::MysqlSystemdProtectHomeCheck;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        return 1 if 0 == @args;
        return   if 1 != @args;

        return $args[0] == 1 || $args[0] == 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ($arg) = $task->args();
        $arg = $arg ? 1 : 0;

        if ( Cpanel::OS::is_systemd() ) {
            require Cpanel::MysqlUtils::Systemd::ProtectHome;

            return 1 if Cpanel::MysqlUtils::Systemd::ProtectHome::set_unset_protecthome_if_needed( defined $arg ? ( { jailapache => $arg } ) : () );
        }

        return 0;
    }

    sub deferral_tags {
        my ( $self, $task ) = @_;
        return qw/mysql/;
    }
}

{

    package Cpanel::TaskProcessors::DBStoreGrants;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        my ($user) = $task->args();
        require Cpanel::AcctUtils::Account;
        return 1 if Cpanel::AcctUtils::Account::accountexists($user);
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my $user = $task->get_arg(0);
        require Cpanel::AcctUtils::Account;
        return unless Cpanel::AcctUtils::Account::accountexists($user);
        require Cpanel::DB::GrantsFile;
        return Cpanel::DB::GrantsFile::dump_for_cpuser($user);
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/mysql/;
    }
}

{

    package Cpanel::TaskQueue::DBIndex;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @users = $task->args();

        my $dbindex = '/usr/local/cpanel/bin/dbindex';
        return unless -x $dbindex;

        require '/usr/local/cpanel/bin/dbindex';    ## no critic qw(Modules::RequireBarewordIncludes)
        return bin::dbindex::run(@users);
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/mysql/;
    }
}

sub to_register {
    return (
        [ 'flushprivs',               Cpanel::TaskProcessors::MysqlTasks::Flush->new() ],
        [ 'sync_db_grants_from_disk', Cpanel::TaskProcessors::MysqlTasks::SyncGrantsFromDisk->new() ],
        [ 'mysqluserstore',           Cpanel::TaskProcessors::MysqlUserStore->new() ],
        [ 'dbstoregrants',            Cpanel::TaskProcessors::DBStoreGrants->new() ],
        [ 'dbindex',                  Cpanel::TaskQueue::DBIndex->new() ],
        [ 'protecthomecheck',         Cpanel::TaskProcessors::MysqlSystemdProtectHomeCheck->new() ],
    );
}

1;
