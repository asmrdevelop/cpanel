package Cpanel::Timezones::SubProc;

# cpanel - Cpanel/Timezones/SubProc.pm              Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

# idea: update $ENV{TZ} without bloating the binary
#   we only need to set/update a TimeZome from time to time
#	we can pay the extra cost of spawning a new process
#   to save the about 2M of memory coming Cpanel::Timezones
#
#	this was originaly designed for libexec/tailwatch/tailwatchd
#	but can find other places where it would make sense

=head1 NAME

Cpanel::Timezones::SubProc

=cut

use strict;
use warnings;

sub perl { return $^X }    # mocked for unit test

=head2 Function: calculate_TZ_env

Set $ENV{TZ} in a subprocess using Cpanel::Timezones

=cut

sub calculate_TZ_env {

    # if we fail to update the TimeZone, preserve the previous one
    my $perl = perl();

    my $tz = qx{$perl -MCpanel::Timezones -E 'print Cpanel::Timezones::calculate_TZ_env()' 2>/dev/null};    ## no critic qw(ProhibitQxAndBackticks)
    return unless $? == 0;
    return unless defined $tz && length $tz;

    $ENV{TZ} = $tz;

    return 1;
}

1;
