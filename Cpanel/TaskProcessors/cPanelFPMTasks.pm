package Cpanel::TaskProcessors::cPanelFPMTasks;

# cpanel - Cpanel/TaskProcessors/cPanelFPMTasks.pm     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::cPanelFPMTasks::AddUser;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $old_cmd = $old->command();
        if ( $old_cmd eq 'cpanelfpm_remove_user' ) {
            my ($new_user) = $new->args();
            my ($old_user) = $old->args();
            if ( $new_user eq $old_user ) {
                return 1;
            }
        }
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ($user) = $task->args();
        require Cpanel::Server::FPM::Manager;

        Cpanel::Server::FPM::Manager::add_user($user);
        return;
    }

}

{

    package Cpanel::TaskProcessors::cPanelFPMTasks::RemoveUser;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $old_cmd = $old->command();
        if ( $old_cmd eq 'cpanelfpm_add_user' ) {
            my ($new_user) = $new->args();
            my ($old_user) = $old->args();
            if ( $new_user eq $old_user ) {
                return 1;
            }
        }
        return 0;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ($user) = $task->args();
        require Cpanel::Server::FPM::Manager;

        Cpanel::Server::FPM::Manager::remove_user($user);
        return;
    }

}

sub to_register {
    return (
        [ 'cpanelfpm_add_user',    Cpanel::TaskProcessors::cPanelFPMTasks::AddUser->new() ],
        [ 'cpanelfpm_remove_user', Cpanel::TaskProcessors::cPanelFPMTasks::RemoveUser->new() ],

    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::cPanelFPMTasks - Task processor for running some FileProtect Account maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::cPanelFPMTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::cPanelFPMTasks;

=head1 DESCRIPTION

Implement the code for the I<cpanelfpm_add_user> and I<cpanelfpm_remove_user>  Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::cPanelFPMTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::cPanelFPMTasks::AddUser

This is a thin wrapper around Cpanel::Server::FPM::Manager::add_user

=head2 Cpanel::TaskProcessors::cPanelFPMTasks::RemoveUser

This is a thin wrapper around Cpanel::Server::FPM::Manager::remove_user

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, L.L.C All rights reserved.
