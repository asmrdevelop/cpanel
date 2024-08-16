package Cpanel::Sys::Hardware::Memory::Vzzo;

# cpanel - Cpanel/Sys/Hardware/Memory/Vzzo.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $bean_counters_file = '/proc/user_beancounters';

my $usage_key = 'privvmpages';

sub get_installed {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'installed'} );
}

sub get_available {
    my $mem_info = _load_meminfo();

    return 'unlimited' if ( $mem_info->{'installed'} && _is_unlimited( $mem_info->{'installed'} ) );

    return _format_mib( $mem_info->{'available'} );
}

sub get_used {
    my $mem_info = _load_meminfo();

    return _format_mib( $mem_info->{'used'} );
}

sub get_swap {
    my $mem_info = _load_meminfo('swappages');

    return _format_mib( $mem_info->{'installed'} );
}

sub _format_mib {
    my ($num) = @_;
    return 'unknown' if ( !$num );

    return ( _is_unlimited($num) ) ? 'unlimited' : int( 4 * $num / 1024 );
}

sub _is_unlimited {
    my ($num) = @_;

    return 1 if $num == '9223372036854775807' + 0;
    return 0;
}

#see http://wiki.openvz.org/Privvmpages#oomguarpages
sub _load_meminfo {
    my $key = shift;
    $key ||= $usage_key;

    open( my $bc_fh, '<', $bean_counters_file ) or do {
        die "Could not open “$bean_counters_file” for reading: $!";
    };

    my %mem_p;
    while ( my $line = readline($bc_fh) ) {
        next if $line !~ m/^\s*\Q$key\E\s+(.*)/;

        my $parm = $1;
        chomp($parm);
        my ( $held, $maxheld, $barrier, $limit, $failcnt ) = split( /\s+/, $parm );
        last if $held eq '-';

        # barrier is allowed to be < limit (akin to soft vs. hard disk quotas)
        # This allows held to be > barrier under some circumstances, resulting in a negative value
        my $available = ( $barrier - $held );
        $available = 0 if $available < 0;

        #NOTE: This is the # of 4-KiB pages.
        $mem_p{'available'} = $available;
        $mem_p{'installed'} = $barrier;
        $mem_p{'used'}      = $held;

        last;
    }
    close($bc_fh);

    return \%mem_p;
}

1;
