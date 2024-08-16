package Cpanel::TaskProcessors::EmailTasks;

# cpanel - Cpanel/TaskProcessors/EmailTasks.pm     Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::EmailTasks::RebuildEmailAccountCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $user, $domain ) = $task->args();
        require Whostmgr::Email;

        # Force updating the cache so the next dovecot conf
        # update does not have to do it
        Whostmgr::Email::count_pops_for_without_ownership_check( $user, $domain );

        return;
    }

}

{

    package Cpanel::TaskProcessors::EmailTasks::ReconfigureCalendarsNotification;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $user, $domain ) = $task->args();
        require Cpanel::DAV::CaldavCarddav::Notification;

        Cpanel::DAV::CaldavCarddav::Notification::reconfigure_calendars_notification();

        return;
    }

}

sub to_register {
    return (
        [ 'rebuild_email_accounts_cache',       Cpanel::TaskProcessors::EmailTasks::RebuildEmailAccountCache->new() ],
        [ 'reconfigure_calendars_notification', Cpanel::TaskProcessors::EmailTasks::ReconfigureCalendarsNotification->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::EmailTasks - Task processor for running some Email Account maintenance

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::EmailTasks;

=head1 DESCRIPTION

Implement the code for the I<rebuild_email_accounts_cache> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::EmailTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::EmailTasks::rebuild_email_accounts_cache

This is a thin wrapper around Whostmgr::Email::count_pops_for_without_ownership_check

=head2 Cpanel::TaskProcessors::EmailTasks::reconfigure_calenadrs_notification

Send a notification to end-users of CalDAV/CardDAV services that they need to reconfigure
their clients.
See C<Cpanel::DAV::CaldavCarddav::Notification::reconfigure_calendars_notification>.
