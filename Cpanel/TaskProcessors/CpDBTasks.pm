package Cpanel::TaskProcessors::CpDBTasks;

# cpanel - Cpanel/TaskProcessors/CpDBTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();
{

    package Cpanel::TaskProcessors::CpDBTasks::UpdateUserDataCache;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    #This never overrides a pre-existing task because the older task
    #will harvest() the entry that has (presumably) just been created.
    #So we want this (new) task to be tossed out in favor of an older one.
    use constant overrides => 0;

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my $numargs = scalar $task->args();
        return undef if $numargs > 0;

        # Even if there is nothing to do we still need to return 1 to avoid
        # a spurious warning about invalid args.  We will just skip the work
        # in the child task

        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Config::userdata::CacheQueue::Harvester;

        # Since this is a queue within a queue and we remove newer tasks in favor
        # of the older task, we need to make sure that there are no more usernames
        # to be harvested before returning
        while (1) {
            my @usernames;
            Cpanel::Config::userdata::CacheQueue::Harvester->harvest(
                sub { push @usernames, shift },
            );

            #If the subqueue is empty, then there’s no reason to run this task.
            last unless @usernames;

            require Cpanel::Config::userdata::UpdateCache;
            eval { Cpanel::Config::userdata::UpdateCache::update(@usernames) };
            warn if $@;
        }

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/userdata_update/;
    }

}

{

    package Cpanel::TaskProcessors::CpDBTasks::BuildGlobalCache;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        my ($user) = $task->args();
        return undef if $numargs != 0;

        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');

        # TODO: make build_global_cache a modulino

        my $run = Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/bin/build_global_cache' );
        $run->die_if_error() unless $run->error_code == 141;    # build_global_cache exits with 141 normally

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/build_global_cache/;
    }

}

{

    package Cpanel::TaskProcessors::CpDBTasks::UpdateDomainIps;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return undef if $numargs != 0;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();

        Cpanel::LoadModule::load_perl_module('Cpanel::DIp::Update');
        Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn();

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dip_update httpd/;
    }

}

{

    package Cpanel::TaskProcessors::CpDBTasks::FtpUpdate;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 1 if 0 == $task->args();
        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        eval {
            # Support for older ftpupdate invocations that relied on the ftpupdate script creating or removing files.
            # cPanel code no longer calls ftpupdate this way, but items may remain in the queue after an update.
            require Cpanel::FtpUtils::UpdateQueue::Harvester;
            my @ftpupdate_calls;

            Cpanel::FtpUtils::UpdateQueue::Harvester->harvest(
                sub { push @ftpupdate_calls, shift },
            );

            if ( scalar @ftpupdate_calls ) {
                require Cpanel::FtpUtils::Passwd;
                foreach my $call (@ftpupdate_calls) {

                    my ( $user, $domain, $domain_ip ) = split( m{\t}, $call );

                    my @args;
                    if ( length $user && length $domain && length $domain_ip ) {
                        Cpanel::FtpUtils::Passwd::remove( $user, $domain_ip );
                    }
                    elsif ( length $user && defined getpwnam($user) ) {
                        Cpanel::FtpUtils::Passwd::create($user);
                    }
                }
            }
        };
        warn if $@;

        # Run ftpupdate
        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'ftpupdate',
                'cmd'    => '/usr/local/cpanel/bin/ftpupdate'
            }
        );
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/ftpupdate/;
    }
}

{

    package Cpanel::TaskProcessors::CpDBTasks::UpdateUserDomains;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 1 if ( $numargs == 0 );
        return 1 if ( $numargs == 1 && $task->get_arg(0) eq '--force' );
        return undef;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Userdomains;
        Cpanel::Userdomains::updateuserdomains( $task->args() );

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/userdomains_update/;
    }

}

{

    package Cpanel::TaskProcessors::CpDBTasks::RebuildIpPool;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return undef if $numargs != 0;
        return 1;
    }

    sub _do_child_task {
        my ($self) = @_;

        require Cpanel::IpPool;
        Cpanel::IpPool::rebuild();

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/userdomains_update/;
    }

}

sub to_register {
    return (
        [ 'ftpupdate',                 Cpanel::TaskProcessors::CpDBTasks::FtpUpdate->new() ],
        [ 'update_userdata_cache',     Cpanel::TaskProcessors::CpDBTasks::UpdateUserDataCache->new() ],
        [ 'build_global_cache',        Cpanel::TaskProcessors::CpDBTasks::BuildGlobalCache->new() ],
        [ 'update_domainips_and_deps', Cpanel::TaskProcessors::CpDBTasks::UpdateDomainIps->new() ],
        [ 'update_userdomains',        Cpanel::TaskProcessors::CpDBTasks::UpdateUserDomains->new() ],
        [ 'rebuildippool',             Cpanel::TaskProcessors::CpDBTasks::RebuildIpPool->new() ],
    );
}

1;
