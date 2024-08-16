package Cpanel::UPID;

# cpanel - Cpanel/UPID.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::UPID - Unique Process ID

=head1 SYNOPSIS

    my $upid = Cpanel::UPID::get($$);

    if ( Cpanel::UPID::is_alive($upid) ) { .. }

=head1 DESCRIPTION

Process IDs (PIDs) are assigned as a round-robin; it’s entirely possible for
two (non-concurrent) processes to have the same PID. There are applications,
though, where it’s advantageous to distinguish the two.

This module takes any PID and returns a forever-unique, stable, and
reproducible ID string for that process. The term “UPID” is proposed for
these.

To verify that a process with a given UPID is still alive, just do:

=head1 IMPLEMENTATION NOTES

Technically there is no way to guarantee what this module offers; however,
to produce a duplicate we’d have to cycle through MAX_PID processes within
a single clock tick. That doesn’t seem likely to happen any time soon. It
*might* be feasible in testing, but real-world use would seem pretty
unlikely.

Note that UPIDs are only meant to be unique within a given system. There is
no guarantee that a UPID on one system won’t have a duplicate on another.
(It’s pretty unlikely, but hey.)

=cut

use strict;
use warnings;

use Cpanel::LoadFile ();

my $_boot_time;

=head1 FUNCTIONS

=head2 $upid = get( $PID )

Returns either:

=over

=item * The unique process ID (UPID) for the process with the given PID,
if a process with the given PID exists.

=item * undef if no process with the given PID exists.

=back

B<NOTE:> The format of the UPID is undefined for now. Please don’t build
things that parse it; if you need the elements that happen to make up the
UPID, please fetch them yourself, and/or refactor this module so that we
don’t duplicate logic.

=cut

sub get {
    my ($pid) = @_;

    die "Need PID, not “$pid”!" if !$pid || $pid =~ tr<0-9><>c;

    my $start_delta = _get_pid_start_delta($pid);
    return undef if !$start_delta;

    $_boot_time ||= get_boot_time();

    # Put the start delta before the boot time because that puts more
    # entropy earlier. This makes it easier to distinguish two UPIDs visually.
    return join( '.', $pid, $start_delta, $_boot_time );
}

=head2 $pid = extract_pid( $UPID )

Parses the $UPID to return the original PID (process ID).

=cut

sub extract_pid {
    my ($upid) = @_;

    return substr( $upid, 0, index( $upid, '.' ) );
}

=head2 $yn = is_alive( $UPID )

A convenience function that returns a boolean that indicates
whether the given $UPID refers to an active process on the system.

=cut

sub is_alive {
    my ($upid) = @_;

    my $pid = extract_pid($upid);
    return ( $upid eq ( Cpanel::UPID::get($pid) // q<> ) );
}

=head2 $btime = get_boot_time()

A convenience function that returns the value of btime from /proc/stat.

=cut

sub get_boot_time {
    my $proc_stat   = Cpanel::LoadFile::load('/proc/stat');
    my $where_btime = index( $proc_stat, 'btime ' );
    die '/proc/stat format changed???' if $where_btime == -1;

    my $where_lf = index( $proc_stat, "\n", $where_btime );

    my $number_start = 6 + $where_btime;

    return substr( $proc_stat, $number_start, $where_lf - $number_start );
}

#----------------------------------------------------------------------

sub _get_pid_start_delta {
    my ($pid) = @_;

    my $proc_pid_stat = Cpanel::LoadFile::load_if_exists("/proc/$pid/stat");
    return undef if !$proc_pid_stat;

    # The 2nd field is a parentheses-enclosed name which can contain spaces.
    # It can also contain parens, so we need the rightmost occurrence of
    # right-paren.
    my $right_paren_at = rindex( $proc_pid_stat, ')' );
    substr( $proc_pid_stat, 0, 2 + $right_paren_at, q<> );

    # We need the 22nd field. We stripped two above.
    return ( split m<\s+>, $proc_pid_stat )[19];
}

1;
