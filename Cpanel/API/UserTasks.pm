package Cpanel::API::UserTasks;

# cpanel - Cpanel/API/UserTasks.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::API::UserTasks

=head1 SYNOPSIS

    use Cpanel::API::UserTasks ();

    Cpanel::API::UserTasks::retrieve( $args, $result );

    Cpanel::API::UserTasks::delete( $args, $result );

=head1 DESCRIPTION

C<Cpanel::API::UserTasks> presents two API entry points for the
user-facing C<Cpanel::UserTasks> task queue.

=cut

use Cpanel::UserTasks ();

=head1 FUNCTIONS

=head2 Cpanel::API::UserTasks::retrieve()

Retrieves the contents of the user's task queue.

=head3 Arguments

=over 4

=item $args

A Cpanel::Args object

=item $result

A Cpanel::Result object

=back

=head3 Returns

1.

=head3 Dies

If any of the C<Cpanel::UserTasks> operations fail, the function will
die.

=cut

sub retrieve {
    my ( $args, $result ) = @_;

    my @tasks;

    my $ut   = Cpanel::UserTasks->new();
    my $task = $ut->first();
    while ( $task ne '' ) {
        my $contents = $ut->get($task);
        $contents->{'id'} = $task;
        push @tasks, $contents;
        $task = $ut->next();
    }

    $result->data( \@tasks );

    return 1;
}

=head2 Cpanel::API::UserTasks::delete()

Removes a task from the task queue.

=head3 Arguments

=over 4

=item $args

A Cpanel::Args object.  The $args object must contain the 'id' key.

=item $result

A Cpanel::Result object

=back

=head3 Returns

1.

=head3 Dies

If any of the C<Cpanel::UserTasks> operations fail, the function will
die.

=cut

sub delete {
    my ( $args, $result ) = @_;

    my $task_id = $args->get_length_required('id');

    Cpanel::UserTasks->new()->remove($task_id);

    return 1;
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::UserTasks>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

my $allow_demo = { allow_demo => 1 };

our %API = (
    retrieve => $allow_demo,
    delete   => $allow_demo,
);

1;
