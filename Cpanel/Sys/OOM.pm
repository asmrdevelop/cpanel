package Cpanel::Sys::OOM;

# cpanel - Cpanel/Sys/OOM.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use strict;
use Cpanel::SafeRun::Object ();
use Cpanel::Sys::Uptime     ();
use Cpanel::PwCache         ();

###########################################################################
#
# Method:
#   fetch_oom_data_from_dmesg
#
# Returns:
#   The same as extract_oom_data_from_dmesg
#
sub fetch_oom_data_from_dmesg {
    my $run = Cpanel::SafeRun::Object->new( 'program' => '/bin/dmesg' );
    return extract_oom_data_from_dmesg( $run->stdout() );
}

###########################################################################
#
# Method:
#   extract_oom_data_from_dmesg
#
# Description:
#   This function accept raw dmesg input and parses
#   each OOM event into an array of hashrefs which is
#   defined in the return format
#
# Parameters:
#   The raw dmesg data
#
# Returns:
#  An arrayref of hashrefs that contain one or more of
#  the following keys. The process_killed and
#  data keys are always provided
#    {
#        'data' => 'A block of OOM messages from dmesg...',
#        'uid'  => 'The uid of the process that OOM killed',
#        'user'  => 'The username of the process that OOM killed',
#        'pid'  => 'The pid of the process that OOM killed',
#        'proc_name' => 'The name of the process that OOM killed',
#        'score' => 'The OOM score of the process that OOM killed',
#        'total_vm' => 'The total system virtual memory consumed by the process that OOM killed',
#        'anon_rss' => 'The anonymous resident set size consumed by the process that OOM killed',
#        'file_rss' => 'The file resident set size consumed by the process that OOM killed',
#        'process_killed' => '1 if OOM killed a process, 0 if no process was killed'
#    }
#
sub extract_oom_data_from_dmesg {
    my ($output) = @_;

    my $parser_state = {
        'in_oom_invoke'    => 0,
        'in_out_of_memory' => 0,
        'oom_record'       => -1,
    };

    my @oom_records;
    foreach my $dmesg_line ( split( m{\n}, $output ) ) {
        if ( index( $dmesg_line, q{invoked oom-killer: } ) > -1 ) {
            $parser_state->{'in_oom_invoke'}    = 1;
            $parser_state->{'in_out_of_memory'} = 0;
            $parser_state->{'oom_record'}++;
        }
        elsif ( index( $dmesg_line, q{Out of memory:} ) > -1 ) {
            $parser_state->{'in_out_of_memory'} = 1;
            if ( $parser_state->{'in_oom_invoke'} ) {
                $parser_state->{'in_oom_invoke'} = 0;
            }
            else {
                $parser_state->{'oom_record'}++;
            }
        }

        if ( $parser_state->{'in_out_of_memory'} && $dmesg_line !~ m{(Out of memory:|Killed process)} ) {
            $parser_state->{'in_out_of_memory'} = 0;
        }

        if ( $parser_state->{'in_oom_invoke'} || $parser_state->{'in_out_of_memory'} ) {
            $oom_records[ $parser_state->{'oom_record'} ]->{'data'} .= $dmesg_line . "\n";
        }
    }

    _augment_oom_records( \@oom_records );

    return \@oom_records;
}

sub _augment_oom_records {
    my ($oom_records_ref) = @_;

    my %pid_to_uid;
    my $uptime = Cpanel::Sys::Uptime::get_uptime();
    my $now    = _time();

    foreach ( @{$oom_records_ref} ) {
        chomp( $_->{'data'} );

        my $is_cgroup           = ( grep ( m/Memory cgroup stats/,  split( m{\n}, $_->{'data'} ) ) )[0] ? 1 : 0;
        my $out_of_memory_line  = ( grep ( m/Out of memory:/,       split( m{\n}, $_->{'data'} ) ) )[0];
        my $killed_process_line = ( grep ( m/Killed process/,       split( m{\n}, $_->{'data'} ) ) )[0];
        my @proc_table          = ( grep ( m/\[[0-9 ]+\] +[0-9]+ /, split( m{\n}, $_->{'data'} ) ) );

        foreach my $proc_line (@proc_table) {
            my ( $pid, $uid ) = $proc_line =~ m{\[ *([0-9]+) *\] +([0-9]+)};
            if ( defined $pid && defined $uid ) {
                $pid_to_uid{$pid} = $uid;
            }
        }

        $_->{'is_cgroup'} = $is_cgroup;

        if ( length $out_of_memory_line ) {
            ( $_->{'seconds_since_boot'} ) = $out_of_memory_line =~ m{\[([0-9]+\.[0-9]+)\]};
            ( $_->{'uid'} )                = $out_of_memory_line =~ m{[ ,]+UID ([0-9]+)};
            ( $_->{'proc_name'} )          = $out_of_memory_line =~ m{[ ,]+process\s+[0-9]+\s+(.*?) score};
            ( $_->{'proc_name'} )          = $out_of_memory_line =~ m{[ ,]+(\(.*?\)).?$} if !defined $_->{'proc_name'};
            ( $_->{'score'} )              = $out_of_memory_line =~ m{[ ,]+score\s+([0-9]+)};
            ( $_->{'pid'} )                = $out_of_memory_line =~ m{[ ,]+process ([0-9]+)};
        }
        if ( length $killed_process_line ) {
            ( $_->{'seconds_since_boot'} ) = $killed_process_line =~ m{\[([0-9]+\.[0-9]+)\]} if !defined $_->{'seconds_since_boot'};
            ( $_->{'uid'} )                = $killed_process_line =~ m{[ ,]+UID ([0-9]+)}    if !defined $_->{'uid'};
            ( $_->{'total_vm'} )           = $killed_process_line =~ m{[ ,]+total-vm:([^ ,]+)};
            ( $_->{'anon_rss'} )           = $killed_process_line =~ m{[ ,]+anon-rss:([^ ,]+)};
            ( $_->{'file_rss'} )           = $killed_process_line =~ m{[ ,]+file-rss:([^ ,]+)};
            ( $_->{'pid'} )                = $killed_process_line =~ m{[ ,]+process ([0-9]+)} if !defined $_->{'pid'};
        }

        if ( $_->{'seconds_since_boot'} ) {
            $_->{'time'} = int( $now - $uptime + $_->{'seconds_since_boot'} );
        }

        # Strip non-matches
        foreach my $key (qw(uid proc_name score pid total_vm anon_rss file_rss seconds_since_boot)) {
            delete $_->{$key} if !defined $_->{$key};
        }

        $_->{'process_killed'} = ( length $out_of_memory_line || length $killed_process_line ) ? 1 : 0;

        if ( !defined $_->{'uid'} && $_->{'pid'} && exists $pid_to_uid{ $_->{'pid'} } ) {
            $_->{'uid'} = $pid_to_uid{ $_->{'pid'} };
        }

        if ( length $_->{'uid'} ) {

            $_->{'user'} = ( Cpanel::PwCache::getpwuid( $_->{'uid'} ) )[0];
        }

        if ( length $_->{'proc_name'} ) {
            $_->{'proc_name'} =~ s{^\(|\)$}{}g;
        }
    }

    return 1;
}

# for testing to be mocked
sub _time {
    return time();
}

1;
