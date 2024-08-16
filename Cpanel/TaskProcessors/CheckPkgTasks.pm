package Cpanel::TaskProcessors::CheckPkgTasks;

# cpanel - Cpanel/TaskProcessors/CheckPkgTasks.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::CheckRPM;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return if $new->command() ne $old->command();

        # no targets overrides a previous task
        return 1 if !defined( ( $new->args() )[0] );

        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ($self) = @_;

        return 1;
    }

    sub deferral_tags {

        # never run more than two commands simultaneously
        return qw{rpm};
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;
        my @targets = $task->args();

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'check_cpanel_pkgs script',
                'cmd'    => '/usr/local/cpanel/scripts/check_cpanel_pkgs',
                'args'   => [ '--fix', scalar @targets ? ( '--targets=' . join( ',', @targets ) ) : () ],
            }
        );

        return;
    }
}

sub to_register {
    return (
        [ 'check_cpanel_pkgs',   Cpanel::TaskProcessors::CheckRPM->new() ],
    );
}

1;
