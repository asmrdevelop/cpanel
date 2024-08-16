package Cpanel::TaskProcessors::NotificationTasks;

# cpanel - Cpanel/TaskProcessors/NotificationTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::NotificationTasks::Notify;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my $encoded_string = $task->get_arg(0);

        require Cpanel::Notify;
        require Cpanel::TaskQueue::Serializer;
        use Try::Tiny;

        my $notification_arg_list = try { Cpanel::TaskQueue::Serializer::decode_param($encoded_string) };

      DECODE_ERR:
        if ( not @$notification_arg_list ) {
            $logger->throw(q{Notification not sent. Can't determine argument list for notification.});
        }

        # ensure decoded reference points to an ARRAY
        elsif ( ref $notification_arg_list ne 'ARRAY' ) {
            $logger->throw(q{Decoded datastructure must be an ARRAY refernce.});
        }

        my $notification_ref = Cpanel::Notify::notification_class(@$notification_arg_list);

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/notify/;
    }
}

{

    package Cpanel::TaskProcessors::NotificationTasks::NotifyFromSubQueue;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::Notify;
        require Cpanel::TaskProcessors::NotificationTasks::Harvester;

        Cpanel::TaskProcessors::NotificationTasks::Harvester->harvest(
            \&Cpanel::Notify::notification_class,
        );

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/notify/;
    }
}

sub to_register {
    return (
        [ 'notify',               Cpanel::TaskProcessors::NotificationTasks::Notify->new() ],
        [ 'notify_from_subqueue', Cpanel::TaskProcessors::NotificationTasks::NotifyFromSubQueue->new() ],
    );
}

1;

__END__

=head1 NAME

Cpanel::TaskProcessor::NotificationTasks

=head1 SYNOPSIS

This module implements a Task for queueprocd, so it's only useful in the context of
sending notifications via C<Cpanel::ServerTasks>.

  use Cpanel::ServerTasks;
  my $notification_param_reference = [ .... stuff for Cpanel::Notify ... ];
  my $uri_encoded_json = Cpanel::ServerTasks::encode_param( $notification_param_reference );
  Cpanel::ServerTasks::queue_task( ['NotificationTasks'], "notify " . $uri_encoded_json );

=head1 DESCRIPTION

This module is a home to any notifications that get sent via queueprocd.

=head1 METHODS

=over 4

=item C<to_register> - registers task with parent, not used externally

=back

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.
