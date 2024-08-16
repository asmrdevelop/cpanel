package Cpanel::TaskProcessors::Cplisc;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::Cplisc::check;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _cpkeyclt_binary {
        return '/usr/local/cpanel/cpkeyclt';
    }

    sub _do_child_task {
        require Cpanel::SafeRun::Object;
        require Cpanel::License;

        # no need to check the license if it appears to be valid
        return 1 if Cpanel::License::is_licensed();

        # Update the license
        Cpanel::SafeRun::Object->new( program => _cpkeyclt_binary() );

        return;
    }

}

{

    package Cpanel::TaskProcessors::Cplisc::update;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _cpkeyclt_binary {
        return '/usr/local/cpanel/cpkeyclt';
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::SafeRun::Object;
        Cpanel::SafeRun::Object->new( program => _cpkeyclt_binary(), args => [q{--force-no-tty-check}] );

        return;
    }

}

{

    package Cpanel::TaskProcessors::Cplisc::refresh;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {

        # Update the license state if needed.
        require Cpanel::License::State;
        Cpanel::License::State::update_state();

        return;
    }

}

sub to_register {
    return (
        [ 'check'   => Cpanel::TaskProcessors::Cplisc::check->new() ],
        [ 'update'  => Cpanel::TaskProcessors::Cplisc::update->new() ],
        [ 'refresh' => Cpanel::TaskProcessors::Cplisc::refresh->new() ],
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::Cplisc - Task processor for cPanel license tasks

=head1 VERSION

This document describes Cpanel::TaskProcessors::Cplisc

=head1 SYNOPSIS

Check and update the cPanel license using a background task:

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['Cplisc'], 'check' );

Update the cPanel license using a background task:

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['Cplisc'], 'update' );

License related service restart tasks:

    use Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['Cplisc'], 'restart' );


=head1 DESCRIPTION

Various check & update tasks for the cpanel license.

=head1 INTERFACE

This module defines two subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::Cplisc::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::Cplisc::check

check if cpanel license is valid or not, and update it if needed.

=head2 Cpanel::TaskProcessors::Cplisc::update

update the cpanel license if needed.

=head2 Cpanel::TaskProcessors::Cplisc::refresh

record if cpanel license has changed and other deferred tasks related to cpsrvd restart.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::Cplisc::check->new() runs /usr/local/cpanel/cpkeyclt

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.
