package Cpanel::TaskProcessors::PortAuthorityTasks;

# cpanel - Cpanel/TaskProcessors/PortAuthorityTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::PortAuthorityUserChange;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();

        # the args should be user and newuser
        my $is_valid = ( $numargs == 2 );
        return $is_valid;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my ( $user, $new_user ) = $task->args();

        require '/usr/local/cpanel/scripts/cpuser_port_authority';    ## no critic qw(Modules::RequireBarewordIncludes) refactoring into modules is very risky

        $logger->info("PortAuthorityUserChange: $user $new_user");
        scripts::cpuser_port_authority->user( 'change', $user, $new_user );
        scripts::cpuser_port_authority::call_ubic( $new_user, "stop", "--force" );
        scripts::cpuser_port_authority::update_ubic_conf( $new_user, $user );
        scripts::cpuser_port_authority::call_ubic( $new_user, "restart", "--force" );
        $logger->info("PortAuthorityUserChange: completed");

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/user_change/;
    }

    package Cpanel::TaskProcessors::PortAuthorityFW;
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

        require '/usr/local/cpanel/scripts/cpuser_port_authority';    ## no critic qw(Modules::RequireBarewordIncludes) refactoring into modules is very risky

        $logger->info("PortAuthorityFW: Begin");
        scripts::cpuser_port_authority->fw();
        $logger->info("PortAuthorityFW: Done");

        return 1;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/fw user_change/;
    }
}

sub to_register {
    return (
        [ 'user_change', Cpanel::TaskProcessors::PortAuthorityUserChange->new() ],
        [ 'fw',          Cpanel::TaskProcessors::PortAuthorityFW->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::PortAuthorityTasks - Task processor for the Port Authority

=head1 VERSION

This document describes Cpanel::TaskProcessors::PortAuthorityTasks

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::PortAuthorityTasks;

=head1 DESCRIPTION

These tasks are typically slow, so they have been put into the task processor so they
can be performed asynchronously.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::PortAuthorityTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::PortAuthorityUserChange

Change from one username to another.

=head2 Cpanel::TaskProcessors::PortAuthorityFW

Setup the firewall.

=head2 Cpanel::TaskProcessors::PortAuthorityRestartUBIC

Restarts UBIC for a user.

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

