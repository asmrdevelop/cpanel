package Cpanel::TaskProcessors::DovecotTasks;

# cpanel - Cpanel/TaskProcessors/DovecotTasks.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::DovecotTasks::FlushEntireAccountAuthCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();
        if ( scalar @args == 1 ) {
            require Cpanel::AcctUtils::Account;
            return 0 if !Cpanel::AcctUtils::Account::accountexists( $args[0] );
            return 1;
        }
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::Dovecot::Utils;
        require Whostmgr::Email::Action;

        my ($user) = $task->args();
        return Whostmgr::Email::Action::do_with_each_mail_account(
            $user,
            sub {
                my (@accounts) = @_;
                Cpanel::Dovecot::Utils::flush_auth_caches(@accounts);
            },
            256    # 256 at a time
        );

    }
}

{

    package Cpanel::TaskProcessors::DovecotTasks::FlushEntireAccountAuthCacheThenKick;
    use parent -norequire => 'Cpanel::TaskProcessors::DovecotTasks::FlushEntireAccountAuthCache';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        # The cache-flush stuff:
        $self->SUPER::_do_child_task( $task, $logger );

        my ($username) = $task->args();

        require Cpanel::Dovecot::Utils;
        Cpanel::Dovecot::Utils::kick_all_sessions_for_cpuser($username);

        return;
    }
}

{

    package Cpanel::TaskProcessors::DovecotTasks::FlushEntireAuthCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return 1 if ref $task && !scalar $task->args();
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Dovecot::Utils;
        Cpanel::Dovecot::Utils::flush_all_auth_caches();

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/flush_entire_dovecot_auth_cache/;
    }

}

{

    package Cpanel::TaskProcessors::DovecotTasks::FlushAuthCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        return 1 if !@args;
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Dovecot::FlushAuthQueue::Harvester;

        my @mailboxes;
        Cpanel::Dovecot::FlushAuthQueue::Harvester->harvest(
            sub { push @mailboxes, shift },
        );

        #If the subqueue is empty, then there’s no reason to run this task.
        if (@mailboxes) {
            require Cpanel::Dovecot::Utils;
            while ( my @mailbox_group = splice @mailboxes, 0, 256 ) {
                Cpanel::Dovecot::Utils::flush_auth_caches(@mailbox_group);
            }
        }

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/flush_dovecot_auth_cache/;
    }

}

{

    package Cpanel::TaskProcessors::DovecotTasks::FlushcPanelAccountAuthQueue;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @args = $task->args();

        return 1 if !@args;
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Harvester;

        my @users;
        Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Harvester->harvest(
            sub { push @users, shift },
        );
        if (@users) {
            require Cpanel::Dovecot::Utils;
            require Whostmgr::Email::Action;
        }
        foreach my $user (@users) {
            local $@;
            eval {
                Whostmgr::Email::Action::do_with_each_mail_account(
                    $user,
                    sub {
                        my (@accounts) = @_;
                        Cpanel::Dovecot::Utils::flush_auth_caches(@accounts);
                    },
                    256    # 256 at a time
                );
            };
            warn if $@;
        }

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/flush_cpanel_account_dovecot_auth_cache_queue/;
    }

}

{

    package Cpanel::TaskProcessors::DovecotConf;
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
        my ($self) = @_;

        require Cpanel::MailUtils::SNI;
        Cpanel::MailUtils::SNI->rebuild_dovecot_sni_conf();
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dovecot/;
    }
}

{

    package Cpanel::TaskProcessors::DovecotRestart;
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

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'restart dovecot script',
                'cmd'    => '/usr/local/cpanel/scripts/restartsrv_dovecot',
            }
        );
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dovecot/;
    }
}

{

    package Cpanel::TaskProcessors::DovecotReload;
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
        my ($self) = @_;

        require Whostmgr::Services::Load;
        Whostmgr::Services::Load::reload_service('dovecot');
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dovecot/;
    }
}

{

    package Cpanel::TaskProcessors::DovecotTasks::FTSRescanQueue;

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

        require Cpanel::Dovecot::FTSRescanQueue::Harvester;

        my @mailboxes;
        Cpanel::Dovecot::FTSRescanQueue::Harvester->harvest(
            sub { push @mailboxes, shift },
        );

        #If the subqueue is empty, then there’s no reason to run this task.
        if (@mailboxes) {
            require Cpanel::Dovecot::Utils;
            foreach my $mailbox (@mailboxes) {
                eval { Cpanel::Dovecot::Utils::fts_rescan_mailbox( account => $mailbox ) };
                warn if $@;
            }
        }

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/fts_rescan_mailbox/;
    }

}

{

    package Cpanel::TaskProcessors::DovecotTasks::CreateMailboxForAllAccounts;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _create_mailbox_for_accounts {

        my ( $accounts, $mailbox ) = @_;

        require Cpanel::Dovecot::Utils;
        foreach my $account (@$accounts) {
            eval { Cpanel::Dovecot::Utils::create_and_subscribe_mailbox( account => $account, mailbox => $mailbox ) };
            if ($@) {
                require Cpanel::Debug;
                require Cpanel::Exception;
                Cpanel::Debug::log_warn( "Could not create “$mailbox” mailbox for account “$account”: " . Cpanel::Exception::get_string($@) );
            }
        }

        return;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my $mailbox = $task->get_arg(0);

        require Whostmgr::AcctInfo;
        my $users_hr = Whostmgr::AcctInfo::get_accounts();

        require Whostmgr::Email::Action;
        foreach my $user ( keys %$users_hr ) {
            Whostmgr::Email::Action::do_with_each_mail_account(
                $user,
                sub {
                    my @accounts = @_;
                    _create_mailbox_for_accounts( \@accounts, $mailbox );
                }
            );
        }

        return;
    }

}

{

    package Cpanel::TaskProcessors::DovecotConf::Imunify;
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
        my ($self) = @_;

        require Cpanel::AdvConfig::dovecot;
        Cpanel::AdvConfig::dovecot::check_for_imunify_template();
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/dovecot/;
    }
}

sub to_register {
    return (
        [ 'flush_dovecot_auth_cache',                          Cpanel::TaskProcessors::DovecotTasks::FlushAuthCache->new() ],
        [ 'flush_entire_dovecot_auth_cache',                   Cpanel::TaskProcessors::DovecotTasks::FlushEntireAuthCache->new() ],
        [ 'flush_entire_account_dovecot_auth_cache',           Cpanel::TaskProcessors::DovecotTasks::FlushEntireAccountAuthCache->new() ],
        [ 'flush_cpanel_account_dovecot_auth_cache_queue',     Cpanel::TaskProcessors::DovecotTasks::FlushcPanelAccountAuthQueue->new() ],
        [ 'flush_entire_account_dovecot_auth_cache_then_kick', Cpanel::TaskProcessors::DovecotTasks::FlushEntireAccountAuthCacheThenKick->new() ],
        [ 'build_mail_sni_dovecot_conf',                       Cpanel::TaskProcessors::DovecotConf->new() ],
        [ 'handle_imunify_dovecot_extension',                  Cpanel::TaskProcessors::DovecotConf::Imunify->new() ],
        [ 'restartdovecot',                                    Cpanel::TaskProcessors::DovecotRestart->new() ],
        [ 'reloaddovecot',                                     Cpanel::TaskProcessors::DovecotReload->new() ],
        [ 'fts_rescan_mailbox',                                Cpanel::TaskProcessors::DovecotTasks::FTSRescanQueue->new() ],
        [ 'create_mailbox_for_all_accounts',                   Cpanel::TaskProcessors::DovecotTasks::CreateMailboxForAllAccounts->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::DovecotTasks - Task processor for managing Dovecot

=head1 VERSION

This document describes Cpanel::TaskProcessors::DovecotTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::DovecotTasks;

=head1 DESCRIPTION

Implement the code for the I<flush_dovecot_auth_cache> task. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::DovecotTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::DovecotTasks::FlushAuthCache

This class implements the I<sflush_dovecot_auth_cache> Task. It sets up the Dovecot
database for a user.  Implemented methods are:

=over 4

=item $proc->is_valid_args( $task )

=back

=head1 FUNCTIONS

=head2 builddovecotconf

A task to rebuild the dovecot configuration file along with the SNI config.

=head2 restartdovecot

A task to restart the dovecot server.

=head2 reloaddovecot

A task to reload the dovecot server (re-reads config without restarting).
This is mostly used to change the sni config.

=head2 create_mailbox_for_all_accounts

A task to create a mailbox for all accounts on the system.

=cut

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved.
