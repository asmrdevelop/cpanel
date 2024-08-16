package Cpanel::PsParser::SysInfo;

# cpanel - Cpanel/PsParser/SysInfo.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Uptime           ();
use Cpanel::Sys::Hardware::Memory ();
use Cpanel::SysConf::Constants    ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module provides functionality to calculate percent of cpu
#   and percent of memory used based on the current system information.
#
# Parameters:
#   none
#
# Exceptions:
#   none
#
# Returns:
#   A Cpanel::PsParser::SysInfo object
#
sub new {
    my ($class) = @_;
    my $self = {
        'clock_ticks'         => $Cpanel::SysConf::Constants::_SC_CLK_TCK,
        'uptime'              => Cpanel::Sys::Uptime::get_uptime(),
        'installed_memory_kb' => ( 1024 * Cpanel::Sys::Hardware::Memory::get_installed() ),
        'page_size'           => $Cpanel::SysConf::Constants::_SC_PAGESIZE,
    };

    return bless $self, $class;
}

###########################################################################
#
# Method:
#   calculate_percent_memory_from_rsspages
#
# Description:
#    Calculates the percent of memory used from rss pages
#
# Parameters:
#    The VmRSS (Resident set size) used in pages.  This
#    data is generally provided from /proc/PID/statm
#
# Exceptions:
#   None
#
# Returns:
#    The percentage of memory used based on the installed memory of the system,
#    formatted to two decimal points.
#
sub calculate_percent_memory_from_rsspages {
    my ( $self, $rsspages ) = @_;
    return sprintf( "%.2f", ( ( $rsspages * $self->{'page_size'} / 1024 / $self->{'installed_memory_kb'} ) * 100 ) );    # rss

}

###########################################################################
#
# Method:
#   calculate_percent_memory_from_rsskb
#
# Description:
#    Calculates the percent of memory used from VmRSS in KB
#
# Parameters:
#    The VmRSS (Resident set size) used in kilobytes.  This
#    data is generally provided from /proc/PID/status
#
# Exceptions:
#   None
#
# Returns:
#    The percentage of memory used based on the installed memory of the system,
#    formatted to two decimal points.
#
sub calculate_percent_memory_from_rsskb {
    my ( $self, $rsskb ) = @_;
    return sprintf( "%.2f", ( ( $rsskb / $self->{'installed_memory_kb'} ) * 100 ) );    # rss

}

###########################################################################
#
# Method:
#   calculate_percent_cpu_from_ticks
#
# Description:
#    Calculates the percent of cpu time used when provided
#    the start time and total ticks a process has consumed.
#
# Parameters:
#    The start time of the process in ticks
#    The number of ticks the process has consumed
#
# Notes:
#    The calculation is based on the system information collected
#    when the object is created.  It is important to understand
#    that percent of cpu calculation will have an margin of error tracking
#    as it is not possible to simultaneously collect the uptime of the
#    system and the cpu time used.  You should endevor to collect
#    and provide the input data to this function as close to object
#    creation as possible in order to reduce the tracking error.
#
# Exceptions:
#   None
#
# Returns:
#    The percentage of cpu time used, formatted to two decimal points.
#

sub calculate_percent_cpu_from_ticks {
    my ( $self, $start_time_in_ticks, $total_running_ticks ) = @_;
    my $seconds_since_start =
      $self->{'uptime'} - ( $start_time_in_ticks / $self->{'clock_ticks'} );    # starttime
    my $seconds_running = $total_running_ticks * 1000 / $self->{'clock_ticks'};
    return sprintf(
        "%.2f",
        (
              ( $seconds_running && $seconds_since_start )
            ? ( $seconds_running / $seconds_since_start / 10 )
            : 0
        )
    );
}

###########################################################################
#
# Method:
#   calculate_elapsed_from_ticks
#
# Description:
#    Calculates the number of seconds a process has been running
#    when provided the start time in ticks
#
# Parameters:
#    The start time of the process in ticks
#
# Notes:
#    The calculation is based on the system information collected
#    when the object is created.  It is important to understand
#    that percent of cpu calculation will have an margin of error tracking
#    as it is not possible to simultaneously collect the uptime of the
#    system and the cpu time used.  You should endevor to collect
#    and provide the input data to this function as close to object
#    creation as possible in order to reduce the tracking error.
#
# Exceptions:
#   None
#
# Returns:
#    The number of seconds a process has been running
#

sub calculate_elapsed_from_ticks {
    my ( $self, $start_time_in_ticks ) = @_;
    return sprintf( "%.2f", ( $self->{'uptime'} - ( $start_time_in_ticks / $self->{'clock_ticks'} ) ) );
}

1;
