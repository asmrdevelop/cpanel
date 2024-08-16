package Cpanel::TaskProcessors::SpamassassinTasks;

# cpanel - Cpanel/TaskProcessors/SpamassassinTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

{

    package Cpanel::TaskProcessors::SpamassassinTasks::UpdateRules;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @update_scripts_in_order = (
            ['/usr/local/cpanel/scripts/update_sa_config'],
            ['/usr/local/cpanel/scripts/sa-update_wrapper'],
            [ '/usr/local/cpanel/scripts/update_spamassassin_config', '--verbose' ],
        );

        foreach my $script_ref (@update_scripts_in_order) {
            my $name = ( split( m{/}, $script_ref->[0] ) )[-1];
            my ( $program, @args ) = @{$script_ref};
            $self->checked_system(
                {
                    'logger' => $logger,
                    'name'   => $name,
                    'cmd'    => $program,
                    'args'   => \@args,
                }
            );
        }
        return 1;
    }
}

{

    package Cpanel::TaskProcessors::SpamassassinTasks::Enable;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my $user = $task->get_arg(0);

        Cpanel::LoadModule::load_perl_module('Cpanel::SpamAssassin::Enable');
        return Cpanel::SpamAssassin::Enable::enable($user);
    }
}

{

    package Cpanel::TaskProcessors::SpamassassinTasks::EnableSpamBox;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my $user = $task->get_arg(0);

        require Cpanel::SpamAssassin::Enable;
        return Cpanel::SpamAssassin::Enable::enable_spam_box($user);
    }
}

sub to_register {
    return (
        [ 'update_spamassassin_rules' => Cpanel::TaskProcessors::SpamassassinTasks::UpdateRules->new() ],
        [ 'enable_spamassassin'       => Cpanel::TaskProcessors::SpamassassinTasks::Enable->new() ],
        [ 'enable_spam_box'           => Cpanel::TaskProcessors::SpamassassinTasks::EnableSpamBox->new() ],
    );
}

1;

__END__

=head1 NAME

Cpanel::TaskProcessors::SpamassassinTasks - Task processor for handling certain spamassassin tasks.

=head1 SYNOPSIS

    # processor side
    use Cpanel::TaskQueue;
    my $queue = Cpanel::TaskQueue->new( { name => 'servers', cache_dir => '/var/cpanel/taskqueue' } );
    Cpanel::TaskQueue->register_task_processor( 'SpamassassinTasks', Cpanel::TaskProcessors::SpamassassinTasks->new() );

    # client/queuing side
    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['SpamassassinTasks'],
        join " ", ( 'enable_spamassassin', $user )
    );

    Cpanel::ServerTasks::queue_task(
        ['SpamBoxTasks'],
        join " ", ( 'enable_spam_box', $user )
    );

=head1 DESCRIPTION

A task processor that handles various tasks for SpamAssassin. Tasks that either take
time to process, or can be done out-of-band with the account creation process.

=head1 TASKS

=head2 to_register

Register the following tasks:

=over 4

=item enable_spamassassin

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['SpamassassinTasks'], 'enable_spamassassin zoidberg',
    );

This event takes one argument, a username.

Enables spamassassin for a given user.

=item enable_spam_box

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task(
        ['SpamassassinTasks'], 'enable_spam_box zoidberg',
    );

This event takes one argument, a username.

Enables Spam Box for a given user.

=back
