package Cpanel::ProcessInfo;

# cpanel - Cpanel/ProcessInfo.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();
use Cpanel::Autodie ();

our $VERSION = '1.0';

=encoding utf-8

=head1 NAME

Cpanel::ProcessInfo - process information

=head1 SYNOPSIS

    my @ancestors = Cpanel::ProcessInfo::get_pid_lineage();

=head1 DESCRIPTION

This module contains report utilities for learning about a given process.

=head1 FUNCTIONS

=cut

=head2 my @ancestors = get_pid_lineage()

Returns IDs of all processes that are ancestors of the current process,
starting with the current process’s parent process and ending one before
the root process (i.e., exclusive of PIDs 0 & 1).

=cut

sub get_pid_lineage {
    Cpanel::Context::must_be_list();

    my @lineage;

    my $ppid = getppid();
    while ( $ppid > 1 ) {
        push @lineage, $ppid;
        $ppid = get_parent_pid($ppid);
    }

    return @lineage;
}

=head2 get_parent_pid($pid)

Returns the parent pid of for a given pid.

If there is no parent pid or the process has ended
this function will return undef.

=cut

sub get_parent_pid {
    _die_if_pid_invalid( $_[0] );

    return getppid() if $_[0] == $$;

    if ( open( my $proc_status_fh, '<', "/proc/$_[0]/status" ) ) {
        local $/;
        my %status = map { lc $_->[0] => $_->[1] }
          map  { [ ( split( /\s*:\s*/, $_ ) )[ 0, 1 ] ] }
          grep { index( $_, ':' ) > -1 }
          split( /\n/, readline($proc_status_fh) );
        return $status{'ppid'};
    }

    return undef;
}

=head2 get_pid_exe($pid)

Returns the path to the executable that is running for a given
pid.

If the process has ended this function will return undef.
Any other failure will prompt a L<Cpanel::Exception> instance to be
thrown.

=cut

sub get_pid_exe {
    _die_if_pid_invalid( $_[0] );
    return Cpanel::Autodie::readlink_if_exists( '/proc/' . $_[0] . '/exe' );
}

=head2 get_pid_cmdline($pid)

Returns command line for a given
pid.

If the process has ended
this function will return undef.

=cut

sub get_pid_cmdline {
    _die_if_pid_invalid( $_[0] );
    if ( open( my $cmdline, '<', "/proc/$_[0]/cmdline" ) ) {
        local $/;
        my $cmdline = readline($cmdline);
        $cmdline =~ tr{\0}{ };
        $cmdline =~ tr{\r\n}{}d;
        substr( $cmdline, -1, 1, '' ) if substr( $cmdline, -1 ) eq ' ';
        return $cmdline;
    }

    # Do not die if we cannot find this since the process
    # may have ended and we would be subject to the same
    # race condition that caused failures in CPANEL-21561
    return '';
}

=head2 get_pid_cwd($pid)

Returns current working directory for a given
pid.

If the process has ended
this function will return undef.

=cut

sub get_pid_cwd {
    _die_if_pid_invalid( $_[0] );
    return readlink( '/proc/' . $_[0] . '/cwd' ) || '/';
}

sub _die_if_pid_invalid {
    die "Invalid PID: $_[0]" if !length $_[0] || $_[0] =~ tr{0-9}{}c;
    return;
}
1;
