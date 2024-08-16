package Cpanel::PsParser;

# cpanel - Cpanel/PsParser.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile       ();
use Cpanel::Proc::Bin      ();
use Cpanel::Proc::Basename ();

use Try::Tiny;

our $READ_PROC          = 1;
our $PROC_PATH          = '/proc';
our @KNOWN_INTERPRETERS = (qw(bash tcsh zsh dash csh sh perl python ruby php));

# These positions are from the proc(5) man page for $PROC_PATH/PID/stat
my $PROC_STAT_OFFSET    = 3;                        # 0-index + pid + command
my $PROC_STAT_STATE     = 3 - $PROC_STAT_OFFSET;
my $PROC_STAT_PPID      = 4 - $PROC_STAT_OFFSET;
my $PROC_STAT_PGRP      = 5 - $PROC_STAT_OFFSET;
my $PROC_STAT_UTIME     = 14 - $PROC_STAT_OFFSET;
my $PROC_STAT_STIME     = 15 - $PROC_STAT_OFFSET;
my $PROC_STAT_NICE      = 19 - $PROC_STAT_OFFSET;
my $PROC_STAT_STARTTIME = 22 - $PROC_STAT_OFFSET;

my $RESERVED_PIDS = 300;                            # kernel/pid.c

###########################################################################
#
# Method:
#   fast_parse_ps
#
# Description:
#    Parses the process table into an array of hashref.  Each
#    entry represents a single process.
#
# Parameters:
#   resolve_uids    - If true the user field will be the system user
#                     username instead of the uid of the process.
#   memory_stats    - If true the 'mem' field will be included. This
#                     field represents the percent of memory as defined
#                     by ps(1)
#   cpu_stats       - If true the 'cpu' field will be included. This
#                     field represents the percent of cpu time as defined
#                     by ps(1)
#   elapsed_stats   - If true the 'elapsed' field will be included.
#                     This field includes the number of seconds a process
#                     has been running.
#   want_pid        - Only return data for the specified pid
#
#   want_uid        - Only return data for the specified uid
#
#   exclude_self    - Exclude the current pid
#
#   exclude_kernel  - Exclude processes started by the kernel (pgrp of 0)
#
#   skip_cmdline    - Skip loading the cmdline file and just return
#                     the name from stat.
#
#   skip_stat       - Skip loading the stat file and just return
#                     the pid, uid, and user.
#
#
# Notes:
#   If $PROC_PATH is not usable, this function will fall though to 'parse_ps'
#   which always includes the 'cpu' and 'mem' data.
#
# Exceptions:
#   None
#
# Returns:
#   An array of hashrefs: [
#       {
#           pid     - integer
#           uid     - integer
#           user    - UID *or* username (cf. 'resolve_uids' flag)
#           nice    - ?
#           command - string
#
#           #only included if 'cpu_stats' is given
#           cpu     - percentage, 2 decimal points
#
#           #only included if 'memory_stats' is given:
#           mem     - percentage, 2 decimal points
#       },
#       ...
#   ]
#
sub fast_parse_ps {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    if ( $READ_PROC && -r "$PROC_PATH/1/stat" ) {
        my %OPTS = @_;
        my @PS;
        my $resolve_uids   = $OPTS{'resolve_uids'};
        my $memory_stats   = $OPTS{'memory_stats'};
        my $elapsed_stats  = $OPTS{'elapsed_stats'};
        my $cpu_stats      = $OPTS{'cpu_stats'};
        my $exclude_self   = $OPTS{'exclude_self'};
        my $exclude_kernel = $OPTS{'exclude_kernel'};
        my $want_pid       = $OPTS{'want_pid'};
        my $want_uid       = $OPTS{'want_uid'};
        my $skip_cmdline   = $OPTS{'skip_cmdline'};
        my $skip_stat      = $OPTS{'skip_stat'};

        if ($skip_stat) {
            if ($exclude_kernel) {
                die "The parameters ”skip_stat” and “exclude_kernel” are mutually exclusive.";
            }
            elsif ($cpu_stats) {
                die "The parameters ”skip_stat” and “cpu_stats” are mutually exclusive.";
            }
            elsif ($elapsed_stats) {
                die "The parameters ”skip_stat” and “elapsed_stats” are mutually exclusive.";
            }
            elsif ( !$skip_cmdline ) {
                die "The parameters ”skip_stat” requires “skip_cmdline”";

            }
        }

        my $sysinfo_obj;
        if ( $cpu_stats || $memory_stats || $elapsed_stats ) {
            require Cpanel::PsParser::SysInfo;
            $sysinfo_obj = Cpanel::PsParser::SysInfo->new();
        }
        require Cpanel::PwCache if $resolve_uids;
        if ( opendir( my $proc_dh, $PROC_PATH ) ) {
            my ( $stat, $cmd, $cmdline, $user );
            my $current_pid = $$;
            foreach my $pid ( grep { $_ !~ tr/0-9//c } readdir($proc_dh) ) {
                if (
                    ( $exclude_self && $pid == $current_pid ) ||    #
                    ( $want_pid && $pid != $want_pid ) || ( $exclude_kernel && $pid < $RESERVED_PIDS )
                ) {
                    next;
                }
                my $uid = ( stat("$PROC_PATH/$pid") )[4];
                if (
                    !defined $uid ||                                #
                    ( defined $want_uid && $uid != $want_uid )      #
                ) {
                    next;
                }
                $user = $uid == 0 ? 'root' : $resolve_uids ? ( Cpanel::PwCache::getpwuid($uid) )[0] : $uid;

                $cmdline = '';
                if ( !$skip_cmdline ) {
                    if ( $cmdline = Cpanel::LoadFile::loadfile( "$PROC_PATH/$pid/cmdline", { 'skip_exists_check' => 1 } ) ) {
                        $cmdline =~ tr/\0/ /;
                        $cmdline =~ s/\s+\z//s if substr( $cmdline, -1 ) =~ tr{ \t\f\r\n}{};    # Strip any trailing whitespace from command and will "chomp" newlines if any
                    }
                }

                if ( !$skip_stat ) {

                    # Note: the pid may die in the middle of checking so its expected for loadfile
                    # to return nothing sometimes.  For this reason, please do not convert to using
                    # Cpanel::LoadFile::load
                    #
                    # $PROC_PATH/PID/stat looks like
                    # 1984 (cpsrvd (SSL) - ) S 1 1979 7144 0 -1 4202560 2968569 155110029 0 12 4748 6037 798645 81442 20 0 1 0 34888190 228925440 7633 536870912 4194304 4198588 140737093152192 140737093151464 270831326035 0 0 128 29187 18446744071580550873 0 0 17 1 0 0 0 0 0
                    # Below we ensure we always split on the final ).
                    ( $cmd, $stat ) = split( /\)(?=[^\)]+$) ?/, Cpanel::LoadFile::loadfile( "$PROC_PATH/$pid/stat", { 'skip_exists_check' => 1 } ) || '', 2 );
                    next unless $stat;

                    $stat = [ split( ' ', $stat ) ];

                    if ( !length $cmdline ) {

                        # We strip out the pid at the start of the line since we do not need it
                        $cmd =~ s/^[0-9]+\s+\(?//g;

                        # If we get the command from $PROC_PATH/pid/stat we enclose it in []s to match ps(1) behavior
                        $cmd = '[' . $cmd . ']';
                    }

                    if ( $exclude_kernel && $stat->[$PROC_STAT_PGRP] == 0 ) { next; }
                }

                $cmdline ||= $cmd;

                my %process_info = (
                    'pid'  => $pid,
                    'user' => $user,
                    'uid'  => $uid,
                    $skip_stat ? () : (
                        'nice'    => $stat->[$PROC_STAT_NICE],
                        'state'   => $stat->[$PROC_STAT_STATE],
                        'ppid'    => $stat->[$PROC_STAT_PPID],
                        'command' => $cmdline,
                    )
                );

                if ($memory_stats) {

                    # We use $PROC_PATH/PID/status to get the VmRSS just like ps(1) does.
                    # $PROC_PATH/PID/statm has the VMRss in the second field, however it is in
                    # page sizes which we do not have an easy way to determine.
                    my $statm = Cpanel::LoadFile::loadfile("$PROC_PATH/$pid/statm");
                    if ( defined $statm && $statm =~ m<\S+\s+(\S+)> ) {
                        $process_info{'mem'} = $sysinfo_obj->calculate_percent_memory_from_rsspages($1);
                    }
                }
                if ($cpu_stats) {
                    $process_info{'cpu'} = $sysinfo_obj->calculate_percent_cpu_from_ticks(
                        $stat->[$PROC_STAT_STARTTIME],
                        $stat->[$PROC_STAT_UTIME] + $stat->[$PROC_STAT_STIME]
                    );
                }
                if ($elapsed_stats) {
                    $process_info{'elapsed'} = $sysinfo_obj->calculate_elapsed_from_ticks( $stat->[$PROC_STAT_STARTTIME] );
                }
                push @PS, \%process_info;
            }
        }
        return \@PS;
    }

    # fall through
    goto \&parse_ps;
}

sub get_pid_info {
    my ($pid) = @_;
    return fast_parse_ps(
        'cpu_stats'     => 1,
        'elapsed_stats' => 1,
        'exclude_self'  => 1,
        'memory_stats'  => 1,
        'resolve_uids'  => 1,
        'want_pid'      => $pid,
    )->[0];
}

sub _get_child_pids {
    my ( $ppid, $ps_ref ) = @_;

    my @out  = grep { $_->{'ppid'} == $ppid } @{$ps_ref};
    my @pids = map  { $_->{'pid'} } @out;
    my @subpids;

    foreach my $pid (@pids) {
        push( @subpids, _get_child_pids( $pid, $ps_ref ) );
    }

    push( @pids, @subpids );

    return @pids;
}

sub get_child_pids {
    my (@ppids) = @_;

    my $ps_ref = Cpanel::PsParser::fast_parse_ps(
        'cpu_stats'     => 1,
        'elapsed_stats' => 1,
        'exclude_self'  => 1,
        'memory_stats'  => 1,
        'resolve_uids'  => 1,
    );

    my @pids;
    my %seen;
    foreach my $pid (@ppids) {
        foreach my $xpid ( _get_child_pids( $pid, $ps_ref ) ) {
            push( @pids, $xpid ) if ( !exists $seen{$xpid} );
            $seen{$xpid} = 1;
        }
    }

    return @pids;
}

# Use fast_parse_ps.  This is only here for legacy support
sub parse_ps {
    require Cpanel::PsParser::Fallback;
    goto \&Cpanel::PsParser::Fallback::parse_ps;
}

sub get_pids_by_name {
    my ( $deadcmd, $allowed_owners ) = @_;

    return unless defined $deadcmd;

    if ( $> != 0 ) { $allowed_owners = { $> => 1 }; }

    my $deadcmd_regex_text = '^(?:' . ( ref $deadcmd eq 'ARRAY' ? join( '|', map { quotemeta($_) } @{$deadcmd} ) : quotemeta($deadcmd) ) . ')$';
    my $deadcmd_regex      = ref $deadcmd eq 'Regexp' ? $deadcmd : qr/$deadcmd_regex_text/i;

    if ( '' =~ $deadcmd_regex ) {
        return;    #can't match ''
    }
    if ( defined $allowed_owners && ref $allowed_owners eq 'ARRAY' ) {
        $allowed_owners = { map { $_ => 1 } @{$allowed_owners} };
    }
    if ( defined $allowed_owners ) {

        # Ensure hash keys are uids
        $allowed_owners = { map { ( $_ !~ tr{0-9}{}c ? $_ : ( _lazy_getpwnam($_) )[2] ) => 1 } keys %$allowed_owners };
    }

    my ( $process_name_first_element, @process_name_secondary_elements, $file, $binary_path, $owner );
    if ( $READ_PROC && -r "$PROC_PATH/1/cmdline" && opendir( my $proc_dh, $PROC_PATH ) ) {
        my @pids;
        foreach my $proc ( grep { $_ !~ tr{0-9}{}c } readdir($proc_dh) ) {    # Only has numbers so its a pid
            next if $proc < $RESERVED_PIDS;
            $binary_path = readlink("$PROC_PATH/$proc/exe") or next;

            # no file means it a kernel process that we always want to exclude
            # stat name is here.  we don't want to ever kill kernel process so not used

            $owner = ( stat("$PROC_PATH/$proc") )[4];    #getbin will stat the /proc/<pid>
            if ( !defined $owner || ( defined $allowed_owners && !exists $allowed_owners->{$owner} ) ) { next; }

            ( $process_name_first_element, @process_name_secondary_elements ) = map { Cpanel::Proc::Basename::getbasename($_) } ( split( /[\s\0]+/, Cpanel::LoadFile::loadfile( "$PROC_PATH/$proc/cmdline", { 'skip_exists_check' => 1 } ) || '' ) );    # Note: process may go away during lookup

            next if !length $process_name_first_element;
            $file = ( split( m{/}, $binary_path ) )[-1];

            if ( _proc_matches_regex( $deadcmd_regex, $process_name_first_element, \@process_name_secondary_elements, $deadcmd, $file ) ) {
                push @pids, $proc + 0;                                                                                                                                                                                                                   # + 0 for 5.12
            }

        }

        return @pids;
    }

    #Fallback to ps
    my @pids;
    my $ps_list = fast_parse_ps( 'exclude_kernel' => 1 );
    return if ( !ref $ps_list );

    foreach my $proc ( @{$ps_list} ) {
        if ( defined $allowed_owners && !exists $allowed_owners->{ $proc->{'uid'} } ) { next; }

        ( $process_name_first_element, @process_name_secondary_elements ) = map { Cpanel::Proc::Basename::getbasename($_) } ( split( /\s+/, $proc->{'command'} ) );
        $file = ( split( /\//, Cpanel::Proc::Bin::getbin( $proc->{'pid'} ) ) )[-1] || '';

        next if !length $process_name_first_element;

        if ( _proc_matches_regex( $deadcmd_regex, $process_name_first_element, \@process_name_secondary_elements, $deadcmd, $file ) ) {
            push @pids, $proc->{'pid'} + 0;    # + 0 for 5.12
        }

    }

    return @pids;
}

sub _lazy_getpwnam {
    eval 'require Cpanel::PwCache' if !$INC{'Cpanel/PwCache.pm'};
    return Cpanel::PwCache::getpwnam(@_);
}

my $_vm_regex;
my $_interpreters_regex;

sub _proc_matches_regex {
    my ( $deadcmd_regex, $process_name_first_element, $process_name_secondary_elements_ref, $deadcmd, $file ) = @_;

    if ( !$_vm_regex ) {
        $_interpreters_regex ||= get_known_interpreters_regex();
        $_vm_regex = qr/(?:^|\/)$_interpreters_regex$/;
    }
    my $is_vm;

    if ( $process_name_first_element =~ tr/-:// ) {
        $process_name_first_element =~ s/^-//;
        $process_name_first_element =~ s/:$//;
    }

    if ( $process_name_first_element =~ m{$_vm_regex}o ) {

        # Remove arguments to vm
        $is_vm = 1;
        while ( @{$process_name_secondary_elements_ref} && index( $process_name_secondary_elements_ref->[0], '-' ) == 0 ) {
            shift( @{$process_name_secondary_elements_ref} );
        }
    }

    return 1 if length($file) && ( $deadcmd eq $file );
    return 1 if $process_name_first_element =~ $deadcmd_regex;
    return 1 if $is_vm && @$process_name_secondary_elements_ref && ( $process_name_secondary_elements_ref->[0] =~ $deadcmd_regex );

    return 0;
}

sub get_known_interpreters_regex {

    my $interpreters = join( '|', @KNOWN_INTERPRETERS );

    return qr/(?:$interpreters)[0-9.]*/;
}

1;
