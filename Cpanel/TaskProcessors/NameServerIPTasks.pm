package Cpanel::TaskProcessors::NameServerIPTasks;

# cpanel - Cpanel/TaskProcessors/NameServerIPTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::NameServerIPUpdate;
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

        require Cpanel::DnsUtils::NameServerIPs;
        Cpanel::DnsUtils::NameServerIPs::updatenameserveriplist();

        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/NameServerIP/;
    }
}

sub to_register {
    return (
        [ 'updatenameserveriplist', Cpanel::TaskProcessors::NameServerIPUpdate->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::NameServerIPTasks - Task processor for restarting NameServerIP

=head1 VERSION

This document describes Cpanel::TaskProcessors::NameServerIPTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::NameServerIPTasks;

=head1 DESCRIPTION

Implement the code for the I<NameServerIPTasks> Tasks. These
are not intended to be used directly.

=head1 INTERFACE

This module defines a subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::NameServerIPTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::NameServerIPUpdate

This class implements the I<updatenameserveriplist> Task. Executes the same code as
F<Cpanel::DnsUtils::NameServerIPs::updatenameserveriplist>. Implemented methods are:

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task and returns undef.

=item $proc->is_valid_args( $task )

Returns true if the task has no arguments.

=back

=head2 Cpanel::TaskProcessors::NameServerIPUpdate

Rebuilds the NameServerIP configuration.

=over 4

=item $proc->overrides( $new, $old )

Returns true if C<$new> is a duplicate of C<$old>.

=back

=head1 DIAGNOSTICS

=over

=item C<< NameServerIP Restart Error: %s >>

If the restart fails, the error message is logged as a warning along with the
actual message.

=back


=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::NameServerIPTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

J. Nick Koston  C<< nick@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2014, cPanel, Inc. All rights reserved.
