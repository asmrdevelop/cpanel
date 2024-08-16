package Cpanel::Sys::Info;

# cpanel - Cpanel/Sys/Info.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Pack ();

my $sysinfo_struct_size = 128;
my $SYS_sysinfo         = 99;

our $LOAD_ADJUST = 65536;    # 1 << SI_LOAD_SHIFT

our @TEMPLATE = (
    uptime => 'l!',          # long uptime

    load1  => 'L!',          # unsigned long loads[3];
    load5  => 'L!',
    load15 => 'L!',

    totalram  => 'L!',       # unsigned long totalram
    freeram   => 'L!',       # unsigned long freeram
    sharedram => 'L!',       # unsigned long sharedram
    bufferram => 'L!',       # unsigned long bufferram
    totalswap => 'L!',       # unsigned long totalswap
    freeswap  => 'L!',       # unsigned long freeswap
    procs     => 'S!',       # unsigned short procs
    pad       => 'S!',       # unsigned short pad   - from /usr/include, missing in man 2 sysinfo
    totalhigh => 'L!',       # unsigned long totalhigh
    freehigh  => 'L!',       # unsigned long freehigh
    mem_unit  => 'I!',       # unsigned int mem_unit
);

#
#  This module provides an interface to the sysinfo system calls
#  It works with Linux 2.6.9 and later.  This was originally created
#  to improve cpsrvd loadavg call which is run every few seconds
#  when logged into WHM
#

#struct sysinfo {
#  long uptime;      /* Seconds since boot */
#  unsigned long loads[3];   /* 1, 5, and 15 minute load averages */
#  unsigned long totalram;   /* Total usable main memory size */
#  unsigned long freeram;    /* Available memory size */
#  unsigned long sharedram;  /* Amount of shared memory */
#  unsigned long bufferram;  /* Memory used by buffers */
#  unsigned long totalswap;  /* Total swap space size */
#  unsigned long freeswap;   /* swap space still available */
#  unsigned short procs;   /* Number of current processes */
#  unsigned short pad;   /* explicit padding for m68k */
#  unsigned long totalhigh;  /* Total high memory size */
#  unsigned long freehigh;   /* Available high memory size */
#  unsigned int mem_unit;    /* Memory unit size in bytes */
#  char _f[20-2*sizeof(long)-sizeof(int)]; /* Padding: libc5 uses this.. */
#};

###########################################################################
#
# Method:
#   sysinfo
#
# Description:
#   Returns a sysinfo structure;
#
# Parameters:
#   none
#
# Exceptions:
#   dies on failure from system call
#
# see sysinfo(2) for more information;
#
sub sysinfo {
    local $!;

    my $sysinfo_buffer = "\0" x $sysinfo_struct_size;

    #NB: syscall() returns -1 on error.
    my $self = syscall( $SYS_sysinfo, $sysinfo_buffer );

    die "Failed to call sysinfo(): $!" if $!;    # This should never happen since the only error is EFAULT pointer to struct sysinfo is invalid

    my $sysinfo_hr = Cpanel::Pack->new( \@TEMPLATE )->unpack_to_hashref($sysinfo_buffer);

    delete $sysinfo_hr->{'pad'};

    $_ /= $LOAD_ADJUST for @{$sysinfo_hr}{qw( load1 load5 load15 )};

    return $sysinfo_hr;
}

1;
