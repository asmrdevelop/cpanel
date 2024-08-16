package Cpanel::Sys::Hardware::Memory::Linux;

# cpanel - Cpanel/Sys/Hardware/Memory/Linux.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $meminfo_file = '/proc/meminfo';

sub _format_mib {
    my ($num) = @_;
    return $num ? int( $num / 1024 ) : 'unknown';
}

sub get_installed {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'installed'} );
}

sub get_available {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'available'} );
}

sub get_used {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'used'} - $mem_info->{'buffers'} - $mem_info->{'cached'} );
}

sub get_swap {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'swaptotal'} );
}

sub _load_meminfo {
    my ($self) = @_;
    my %mem_p;

    open( my $bc_fh, '<', $meminfo_file ) or do {
        die "Could not open “$meminfo_file” for reading: $!";
    };

    while ( my $line = <$bc_fh> ) {
        if ( $line =~ /^\s*([^\:]+):\s+(\d+)/ ) {
            $mem_p{ lc($1) } = $2;    #NOTE: Kernel reports usage in KiB.
        }
    }
    close($bc_fh);

    $mem_p{'installed'} = $mem_p{'memtotal'};
    $mem_p{'used'}      = sprintf( '%u', $mem_p{'memtotal'} - $mem_p{'memfree'} );
    $mem_p{'available'} = $mem_p{'memfree'} + $mem_p{'buffers'} + $mem_p{'cached'};

    return \%mem_p;
}

1;
