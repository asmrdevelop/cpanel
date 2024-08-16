package Cpanel::TaskProcessors::TestTasks;

# cpanel - Cpanel/TaskProcessors/TestTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::TestTasks::Sleep;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ($self) = @_;
        return 0;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my ($time) = $task->args();
        sleep($time);

        return 1;
    }
}

sub to_register {
    return (
        [ 'sleep', Cpanel::TaskProcessors::TestTasks::Sleep->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::TestTasks - Task processor for testing queueprocd

=head1 VERSION

This document describes Cpanel::TaskProcessors::TestTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::TestTasks;

=head1 DESCRIPTION

Implement the code to queue a rebuild of Test toolkit Tests. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::TestTasks::to_register

Used by the L<Cpanel::TaskQueue::TaskManager> to register the included classes.

=head2 Cpanel::TaskProcessors::TestTasks::sleep

This class sleeps

=over 4

=item $proc->overrides( $new, $old )

Always reutrns false

=item $proc->is_valid_args( $task )

Returns true if not args are passed.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::TestTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.
