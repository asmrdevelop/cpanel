package Cpanel::TaskProcessors::FileProtectTasks;

# cpanel - Cpanel/TaskProcessors/FileProtectTasks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::FileProtectTasks::SyncUserHomedir;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::FileProtect::Queue::Harvester;

        my @users;
        Cpanel::FileProtect::Queue::Harvester->harvest(
            sub { push @users, shift },
        );

        if (@users) {
            require Cpanel::FileProtect::Sync;
            foreach my $user (@users) {
                local $@;

                # In case Cpanel::FileProtect::Sync dies be sure to process
                # the rest of the user in the queue since its possible
                # a user could have been deleted by the time we process the queue
                my @warnings = eval { Cpanel::FileProtect::Sync::sync_user_homedir($user) };
                if ($@) {
                    warn;
                }
                $logger->warn("FileProtect for $user: $_") for @warnings;
            }
        }

        return;
    }

}

sub to_register {
    return ( [ 'fileprotect_sync_user_homedir', Cpanel::TaskProcessors::FileProtectTasks::SyncUserHomedir->new() ] );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::FileProtectTasks - Task processor for running some FileProtect Account maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::FileProtectTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::FileProtectTasks;

=head1 DESCRIPTION

Implement the code for the I<fileprotect_sync_user_homedir> Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::FileProtectTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::FileProtectTasks::fileprotect_sync_user_homedir

This is a thin wrapper around Cpanel::FileProtect::Sync::sync_user_homedir

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C All rights reserved.
