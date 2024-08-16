package Cpanel::TaskProcessors::TemplateTasks;

# cpanel - Cpanel/TaskProcessors/TemplateTasks.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::TemplateTasks::Rebuild;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 0;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'rebuild-templates',
                'cmd'    => '/usr/local/cpanel/bin/rebuild-templates',
                'args'   => ['--quiet'],
            }
        );

        return 1;
    }
}

sub to_register {
    return (
        [ 'rebuild_templates', Cpanel::TaskProcessors::TemplateTasks::Rebuild->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::TemplateTasks - Task processor for Rebuilding templates

=head1 VERSION

This document describes Cpanel::TaskProcessors::TemplateTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::TemplateTasks;

=head1 DESCRIPTION

Implement the code to queue a rebuild of template toolkit templates. These
are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::TemplateTasks::to_register

Used by the L<Cpanel::TaskQueue::TaskManager> to register the included classes.

=head2 Cpanel::TaskProcessors::TemplateTasks::Rebuild

This class rebuilds all the template toolkit templates

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

Otherwise, return false.

=item $proc->is_valid_args( $task )

Returns true if not args are passed.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::TemplateTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc. All rights reserved.
