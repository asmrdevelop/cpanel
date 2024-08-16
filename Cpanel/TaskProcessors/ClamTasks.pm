package Cpanel::TaskProcessors::ClamTasks;

# cpanel - Cpanel/TaskProcessors/ClamTasks.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

{

    package Cpanel::TaskProcessors::FreshClam;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return if $new->command() ne $old->command();
        return $self->is_dupe( $new, $old );
    }

    sub get_child_timeout {
        ## two hours in seconds
        return 2 * 60 * 60;
    }

    ## as a subroutine, for mocking reasons
    sub _get_executable_freshclam {
        Cpanel::LoadModule::load_perl_module('Cpanel::Binaries');

        my $freshclam_bin = Cpanel::Binaries::path('freshclam');
        if ( -x $freshclam_bin ) {
            return $freshclam_bin;
        }
        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my $freshclam_bin = $self->_get_executable_freshclam();
        return unless defined $freshclam_bin;

        my $args_ref = scalar $task->args() ? [ $task->args() ] : undef;
        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'freshclam',
                'cmd'    => $freshclam_bin,
                $args_ref ? ( 'args' => $args_ref ) : (),
            }
        );
        return 1;
    }
}

sub to_register {
    return (
        [ 'freshclam', Cpanel::TaskProcessors::FreshClam->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::ClamTasks - Task processor for ClamAV binaries

=head1 VERSION

This document describes Cpanel::TaskProcessors::ClamTasks version 0.0.1


=head1 SYNOPSIS

use Cpanel::TaskProcessors::ClamTasks;

=head1 DESCRIPTION

Wrapper around the 'freshclam' binary, so that it may be backrounded.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::ClamTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::FreshClam;

This class implements the I<freshclam> Task.

=over 4

=item $proc->overrides( $new, $old )

Determines if the C<$new> task overrides the C<$old> task. Override for this
class is defined as follows:

If the new task has exactly the same command and args, it overrides the old
task.

Otherwise, return false.

=item $proc->get_child_timeout()

Returns the amount of time 'freshclam' should run before it times out.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::ClamTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

L<Cpanel::Binaries>.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

Phil King  C<< phil@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright 2017, cPanel, Inc. All rights reserved.
