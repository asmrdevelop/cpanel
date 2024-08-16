package Cpanel::Epoll;

# cpanel - Cpanel/Epoll.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my ( $SYS_epoll_create1, $SYS_epoll_ctl, $SYS_epoll_wait );
our $EPOLL_EVENT_TEMPLATE;
our $EPOLL_EVENT_BYTES;

#
# * Note that epoll_data is a union so its all stored in Q *
#
# typedef union epoll_data {
#     void    *ptr;
#     int      fd;                                         perl => I
#     uint32_t u32;                                        perl => L is sizeof(uint32_t)
#     uint64_t u64;                                        perl => Q is sizeof(uint64_t)
# } epoll_data_t;
#
# struct epoll_event {
#     uint32_t     events;    /* Epoll events */           perl => L is sizeof(uint32_t)
#     epoll_data_t data;      /* User data variable */     perl => SEE union epoll_data
# };
#
# is LQ

BEGIN {
    $SYS_epoll_create1    = 291;
    $SYS_epoll_ctl        = 233;
    $SYS_epoll_wait       = 232;
    $EPOLL_EVENT_TEMPLATE = 'LQ';
    $EPOLL_EVENT_BYTES    = length( pack( $EPOLL_EVENT_TEMPLATE, 0 ) );
}

#
#  This module provides an interface to the epoll family of system calls
#  It works with Linux 2.6.9 and later.  This was originally created
#  to improve cpsrvd's responsiveness and make the WHM API binary faster
#  as it allows the following optimizations:
#
#   epoll_wait() will return as soon as we get a signal so we do not
#   have to check manually for child process.
#
#   We can avoid using select(), which requires all the file handles
#   we need to select() being built up into a vector for each call
#   epoll allows us to just poll the epoll fd instead of building it
#   for every call.  In testing cpsrvd responded ~15-20% faster.
#
#   Note: there are multiple modules on CPAN that implement this
#   functionality; however, they do it with XS or do lots of
#   things that we do not want to import.
#

# Constants
our $EPOLLIN  = 1;
our $EPOLLOUT = 4;
our $EPOLLERR = 8;
our $EPOLLHUP = 16;

our $EPOLL_CTL_ADD = 1;
our $EPOLL_CTL_DEL = 2;
our $EPOLL_CTL_MOD = 3;

our $EPOLL_CLOEXEC = 524288;    # O_CLOEXEC

# END Constants

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module provides an interface to the epoll system calls
#
# Parameters:
#   none
#
# Exceptions:
#   dies on failure to create an epoll handle
#
# Returns:
#   A Cpanel::Epoll object
#
# See epoll_create(2) for more information. Note that the underlying
# epoll handle has its CLOEXEC flag turned ON. You can either change
# this (e.g., via Cpanel::FHUtils::FDFlags::set_non_CLOEXEC()) or by
# augmenting this constructor to accept an instruction to forgo CLOEXEC
# on creation of the epoll.
#
sub new {
    my ($class) = @_;

    local $!;

    #NB: syscall() returns -1 on error.
    my $self = syscall( $SYS_epoll_create1, 0 + $EPOLL_CLOEXEC );

    die "Failed to create epoll: $!" if -1 == $self;

    return bless \$self, $class;
}

###########################################################################
#
# Method:
#   add
#
# Description:
#   Adds a file handle to to the epoll object
#   in order to recieve events about it
#
# Parameters:
#   $fh     - A file handle
#   $events - A bit mask of events
#
# Exceptions:
#   none
#
# Returns:
#   The result from the epoll_ctl system call
#   see epoll_ctl(2) for more information
#
sub add {
    my ( $self, $fh, $events ) = @_;

    return $self->_ctl( $EPOLL_CTL_ADD, fileno($fh), $events );
}

###########################################################################
#
# Method:
#   wait
#
# Description:
#   Wait for events from the epoll handle
#
# Parameters:
#   1 - A hashref to hold the epoll events
#       in the format { FD => STATE, FD => STATE, .. }
#   2 - The maximum number of events
#   3 - A timeout in miliseconds
#
# Exceptions:
#   none
#
# Returns:
#   The result from the epoll_wait system call
#   see epoll_wait(2) for more information
#
sub wait {    ## no critic(RequireArgUnpacking)  -- this is a system call and must be fast

    # buffer for epoll events
    my $epoll_wait_ev = "\0" x ( $EPOLL_EVENT_BYTES * $_[2] );

    # Arguments see epoll_wait(2)
    #   $_[0] = epoll_fd
    #   $_[1] = hashref to hold events in the format { FD => STATE, FD => STATE, .. }
    #   $_[2] = max_events
    #   $_[3] = timeout

    my $event_count = syscall( $SYS_epoll_wait, ${ $_[0] } + 0, $epoll_wait_ev, $_[2] + 0, $_[3] + 0 );

    my ( $events, $fd );
    while ( length $epoll_wait_ev ) {
        ( $events, $fd ) = unpack( $EPOLL_EVENT_TEMPLATE, substr( $epoll_wait_ev, 0, $EPOLL_EVENT_BYTES, '' ) );
        $_[1]->{$fd} = $events if $fd;
    }

    return $event_count;
}

###########################################################################
#
# Method:
#   close
#
# Description:
#   Close out the epoll handle
#
# Parameters:
#   none
#
# Exceptions:
#   none
#
# Returns:
#   The result from close call
#
sub close {
    my ($self) = @_;

    my $fd = $$self;
    my $fh;

    my $result = open( $fh, '+<&=', $fd ) && close($fh);

    if ($result) {
        $$self = undef;
    }

    return $result;
}

sub _ctl {
    my ( $self, $op, $fd, $events ) = @_;

    if ( !defined $$self ) {
        die "Already closed!";
    }

    # Arguments see epoll_ctl(2)
    #   $_[0] = epoll_fd
    #   $_[1] = op
    #   $_[2] = fd
    #   $_[3] = events
    my $ret = syscall( $SYS_epoll_ctl, ${$self} + 0, $op + 0, $fd + 0, pack( $EPOLL_EVENT_TEMPLATE, $events, $fd, 0 ) );

    if ( $ret != 0 ) {
        die "epoll_ctl failed: $!";
    }
    return $ret;
}

sub DESTROY {
    my ($self) = @_;

    if ($$self) {
        $self->close();
    }

    return;
}

1;
