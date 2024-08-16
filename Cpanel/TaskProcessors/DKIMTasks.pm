package Cpanel::TaskProcessors::DKIMTasks;

# cpanel - Cpanel/TaskProcessors/DKIMTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub _run_refresh_validity_cache_script {
    my (@args) = @_;

    require Cpanel::ConfigFiles;
    require Cpanel::SafeRun::Object;

    return Cpanel::SafeRun::Object->new_or_die(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/refresh-dkim-validity-cache",
        args    => \@args,
        stderr  => \*STDERR,
    );
}

{

    package Cpanel::TaskProcessors::DKIMTasks::RefreshValidityCache;

    use parent qw(
      Cpanel::TaskQueue::FastSpawn
    );

    sub is_valid_args {
        my ( $self, $task ) = @_;

        if ( my @domains = $task->args() ) {
            require Cpanel::Config::LoadUserDomains;
            my $domain_user_hr = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
            require Cpanel::Sys::Hostname;
            my $hostname = Cpanel::Sys::Hostname::gethostname();

            return 1 if !grep { !$domain_user_hr->{$_} && $_ ne $hostname } @domains;
        }

        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @domains = $task->args();

        Cpanel::TaskProcessors::DKIMTasks::_run_refresh_validity_cache_script( map { ( '--domain' => $_ ) } @domains );

        return;
    }
}

{

    package Cpanel::TaskProcessors::DKIMTasks::RefreshEntireValidityCache;

    use parent qw(
      Cpanel::TaskQueue::FastSpawn
    );

    sub deferral_tags {
        return qw/refresh_dkim_validity_cache/;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return !$task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @domains = $task->args();

        Cpanel::TaskProcessors::DKIMTasks::_run_refresh_validity_cache_script('--all-domains');

        return;
    }
}

{

    package Cpanel::TaskProcessors::DKIMTasks::PropagateToWorkerNodes;

    use parent qw( Cpanel::TaskQueue::FastSpawn );

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return !$numargs;
    }

    sub _do_child_task {
        require Cpanel::DKIM::Propagate::Data;
        require Cpanel::DKIM::Propagate::Send;

        Cpanel::DKIM::Propagate::Data::process_propagations(
            \&Cpanel::DKIM::Propagate::Send::dkim_keys_to_remote,
        );

        return;
    }
}

{

    package Cpanel::TaskProcessors::DKIMTasks::SetupKeys;

    use parent qw( Cpanel::TaskQueue::FastSpawn );

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
        my ($user) = $task->args();

        require Cpanel::DKIM::Transaction;

        my $dkim = Cpanel::DKIM::Transaction->new();

        my @w;
        my $result = do {
            local $SIG{'__WARN__'} = sub { push @w, @_ };
            $dkim->set_up_user($user);
        };

        $dkim->commit();

        if ( !$result || !$result->was_any_success() ) {
            $logger->warn("“$user”’s DKIM setup failed: @w");
        }

        return;
    }
}

{

    package Cpanel::TaskProcessors::DKIMUpdateKeys;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my $script = '/usr/local/cpanel/scripts/update_dkim_keys';
        return unless -x $script;

        return $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'update_dkim_keys script',
                'cmd'    => $script,
            }
        );
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dkim/;
    }
}

{

    package Cpanel::TaskProcessors::EnableSPFDKIMGlobally;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require q{/usr/local/cpanel/scripts/enable_spf_dkim_globally};    ## no critic qw(RequireBarewordIncludes)

        my $enable = scripts::enable_spf_dkim_globally->new();

        my $ret = $enable->run();

        if ( 1 != $ret ) {
            $logger->warn(q{Updating SPF and DKIM for all accounts did not complete successfully.});
        }
        else {
            $logger->info(q{Updating SPF and DKIM has completed successfully.});
        }

        return $ret;
    }
}

sub to_register {
    return (
        [ 'setup_dkim_keys'                    => Cpanel::TaskProcessors::DKIMTasks::SetupKeys->new() ],
        [ 'update_keys'                        => Cpanel::TaskProcessors::DKIMUpdateKeys->new() ],
        [ 'enable_spf_dkim_globally'           => Cpanel::TaskProcessors::EnableSPFDKIMGlobally->new() ],
        [ 'refresh_dkim_validity_cache'        => Cpanel::TaskProcessors::DKIMTasks::RefreshValidityCache->new() ],
        [ 'refresh_entire_dkim_validity_cache' => Cpanel::TaskProcessors::DKIMTasks::RefreshEntireValidityCache->new() ],
        [ 'propagate_dkim_to_worker_nodes'     => Cpanel::TaskProcessors::DKIMTasks::PropagateToWorkerNodes->new() ],
    );
}

1;
