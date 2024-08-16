package Cpanel::CpuWatch::Suspend;

# cpanel - Cpanel/CpuWatch/Suspend.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module is used to suspend cpuwatch operation for
#   tasks that cannot be safely stopped and resumed (e.g.,
#   dumping a MySQL database)
#
#   This module will send SIGUSR1 to the parent
#   cpuwatch to tell it to stop sending the process group
#   SIGSTOP.  When the object is destroyed it will re-enable
#   cpuwatch by sending it SIGUSR2.
#
#   If this module is not running under cpuwatch it will
#   silently do nothing.
#
# Parameters:
#   none

# Returns:
#   A Cpanel::CpuWatch::Suspend object
#
sub new {
    my $class = shift;

    my $self = bless {
        '_ppid'    => getppid(),
        '_pid'     => $$,
        '_enabled' => $ENV{'RUNNING_UNDER_CPUWATCH'} ? 1 : 0,
    }, $class;

    $self->_suspend_cpuwatch_if_enabled();

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    return $self->_unsuspend_cpuwatch_if_enabled();
}

sub _suspend_cpuwatch_if_enabled {
    my ($self) = @_;

    return 0 if !$self->{'_enabled'};
    return   if $self->{'_pid'} != $$;

    return kill 'USR1', $self->{'_ppid'};
}

sub _unsuspend_cpuwatch_if_enabled {
    my ($self) = @_;

    return 0 if !$self->{'_enabled'};
    return   if $self->{'_pid'} != $$;

    return kill 'USR2', $self->{'_ppid'};
}

1;
