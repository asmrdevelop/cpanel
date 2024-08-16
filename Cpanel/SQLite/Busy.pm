package Cpanel::SQLite::Busy;

# cpanel - Cpanel/SQLite/Busy.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SQLite::Busy - Constants for use with cPanel's sqlite setup.

=head1 SYNOPSIS

    use Cpanel::SQLite::Busy;

    my $timeout = Cpanel::SQLite::Busy::TIMEOUT();

    See https://www.sqlite.org/c3ref/busy_timeout.html

    Our default busy timeout is 65s which is 5s
    more than PHP's default (http://php.net/manual/en/function.sqlite-busy-timeout.php)
    In the real world disks are not always as fast as we would
    hope so a 60s+ timeout is needed to accomodate.

=cut

use constant TIMEOUT => 65000;

1;
