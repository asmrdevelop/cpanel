package Cpanel::Mysql::Flush;

# cpanel - Cpanel/Mysql/Flush.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ServerTasks ();

=pod

=head1 NAME

Cpanel::Mysql::Flush

=head2 flushprivs

Queue a task to flush mySQL privs

=head3 Arguments

none

=head3 Return Value

This function always returns 1 unless an exception is generated

=cut

our $TIMEOUT = 5;

my $last_flush_time;

sub flushprivs {
    my $now = _now();
    if ( $last_flush_time && $last_flush_time + ( $TIMEOUT - 1 ) > $now ) {

        # No need to queue again
        return 0;
    }

    $last_flush_time = $now;
    return Cpanel::ServerTasks::schedule_task( ['MysqlTasks'], $TIMEOUT, 'flushprivs' );
}

sub _now {
    return time();
}

1;
