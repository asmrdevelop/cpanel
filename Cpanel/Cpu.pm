package Cpanel::Cpu;

# cpanel - Cpanel/Cpu.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadCpConf ();

sub getcpucount {
    my $cpunum = get_physical_cpu_count(@_);

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();

    $cpunum += $cpconf_ref->{'extracpus'} || 0;

    return $cpunum;
}

our $physical_cpu_count_cache;

sub get_physical_cpu_count {
    return $physical_cpu_count_cache if defined $physical_cpu_count_cache;

    my $cpunum = 1;

    # cpuinfo isn't readable under cloudlinux
    if ( open my $cpuinfo, '<', CPUINFO() ) {
        while ( my $line = readline $cpuinfo ) {
            if ( $line =~ m/^processor\s*:\s*(\d+)/i ) {
                $cpunum = $1;
            }
        }
        close $cpuinfo;
        $cpunum++;
    }
    elsif ( open my $procstat, '<', PROC_STAT() ) {
        while ( my $line = readline $procstat ) {
            if ( $line =~ m/^cpu([0-9]+)/ ) {
                $cpunum = $1;
            }
        }
        close $procstat;
        $cpunum++;
    }

    return $physical_cpu_count_cache = $cpunum;
}

sub CPUINFO   { return '/proc/cpuinfo'; }
sub PROC_STAT { return '/proc/stat'; }
1;
