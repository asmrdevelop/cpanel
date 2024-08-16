package Cpanel::Lsof;

# cpanel - Cpanel/Lsof.pm                          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use List::Util      ();
use Cpanel::Slurper ();

use constant RESERVED_PIDS => 300;

=head1 NAME

Cpanel::Lsof

=head1 SYNOPSIS

This module is intended to (currently) implement a subsection of functionality
typically implemented by the `lsof`. Recently work has been picked up on it
by folks other than the creator (Vic Abell) and introduced both serious bugs
and changes in functionality.

As such we needed to reimplement this subsystem for ourselves, though since
we only need certain types of output/formatters, we have only implemented that
which we need for our systems to function properly.

=head1 DESCRIPTION

This module implements an analogue to things like:
  lsof -F p -- $FILE
  lsof -UF p -- $FILE

In the first case, we have named the subroutine `lsof_formatted_pids`.
In the second case, we have named the subroutine differently --
`get_pids_using_socket_inode`.

In the first case, it was a simple replacement of what we shelled out to lsof
for previously. In the latter, we wanted a bit more control over the output
and to utilize caching of fetched fd -> pid mappings.

This module also caches fetched data from /proc in memory, so callers should
be aware of this.
Big thing to remember is that unless the subroutine(s) you are using
explicitly says it will clear the cache before fetching in this documentation,
it will rely on cached data instead (when it exists).
Make sure you use the `clear_cache` function as is necessary for your purposes
as such.

There is also one notable difference to lsof behaviorally:
We do not provide data for pids lower than 300, as all of those are reserved
by the Kernel for specific processes relating to OS/Kernel helpers which
cPanel realistically has no interest in at this time.

=head1 SEE ALSO

Cpanel::AppPort
Cpanel::Kill::OpenFiles

=head1 SUBROUTINES

=head2 clear_cache

Clears the cached files -> pid mapping. Run this if you need to ensure fresh
data from /proc.

Returns undef.

=cut

my @pids;
my %things_to_procs_hash;
my %fn_map = (
    'files' => \&get_files_for_pid,
    'cwd'   => \&get_cwd_for_pid,
    'rtd'   => \&get_rtd_for_pid,
    'txt'   => \&get_txt_for_pid,
    'mem'   => \&get_mem_for_pid,
);

sub clear_cache {
    undef @pids;
    return undef %things_to_procs_hash;
}

sub _open_x ( $x, $refetch = 0 ) {
    die "Need something to get open stuff for" if !$x;
    undef $things_to_procs_hash{$x}            if $refetch;
    return $things_to_procs_hash{$x}           if $things_to_procs_hash{$x};
    $things_to_procs_hash{$x} = {};
    @pids = Cpanel::Slurper::read_dir('/proc') if !@pids || $refetch;
    foreach my $pid (@pids) {
        $fn_map{$x}->( $pid, $things_to_procs_hash{$x} );
    }

    return %things_to_procs_hash{$x};
}

=head2 open_files

Retrieves the list of open "files" (or pipes, or sockets) and the PIDs holding
these files. Essentially just walking /proc for all $PID entries then running
readlink on all the fds underneath it (ex. /proc/1234/fd/12 -> /some/dir )

Accepts a parameter to indicate whether you wish to refetch this data instead
of rely on the cache (truthy).

Returns HASHREF of ARRAYREFS of PIDs keyed to file/pipe/socket.

=cut

sub open_files ( $refetch = 0 ) {
    return _open_x( 'files', $refetch );
}

=head2 open_dirs

Retrieves the list of open dirs and the PIDs that currently occupy them as the
current working directory. Essentially this is just walking /proc for all $PID
entries then running readlink on cwd. (ex. /proc/1234/cwd -> /some/dir )

Accepts a parameter to indicate whether you wish to refetch this data instead
of rely on the cache (truthy).

Returns HASHREF of ARRAYREFS of PIDs keyed to directory.

=cut

sub open_dirs ( $refetch = 0 ) {
    return _open_x( 'cwd', $refetch );
}

sub _open_all ( $refetch = 0 ) {
    clear_cache() if $refetch;
    foreach my $x ( keys(%fn_map) ) {
        _open_x($x);
    }
    return;
}

=head2 lsof_formatted_pids

Equivalent to:
lsof -F p -- /path, only without the `p` tacked on to the beginning of the pid.
Since this is a "replacement" method for shelling out to lsof, it clears
cache every time this is run.

Accepts argument to indicate what path you are searching for open files on.

Returns ARRAYREF of PIDs.

=cut

sub lsof_formatted_pids ($file) {
    _open_all(1);
    return [] if !$file;
    my @procs;
    foreach my $thing ( keys(%fn_map) ) {

        # Interestingly, the behavior is "starts with this path",
        # not a 1:1 match
        push @procs, List::Util::uniq( map { $things_to_procs_hash{$thing}->{$_}->@* } grep { index( $_, $file ) == 0 } keys( %{ $things_to_procs_hash{$thing} } ) );
    }
    return [ sort { $a <=> $b } @procs ];
}

# well, files sockets AND pipes that is...
sub _get_x_for_pid ( $x, $pid, $x_to_procs_hr ) {
    length $pid or return;
    return unless $pid =~ m{^[0-9]+$};

    # We have no interest in PIDs reserved by the kernel.
    return if ( $pid <= RESERVED_PIDS );
    my $dir2check = "/proc/$pid";
    my @links     = ($x);
    if ( $x eq 'fd' ) {
        $dir2check = "/proc/$pid/$x";
        @links     = eval { Cpanel::Slurper::read_dir($dir2check) };
    }
    return unless @links;
    foreach my $link (@links) {
        next unless length $link;
        my $path = readlink "$dir2check/$link" or next;
        $x_to_procs_hr->{$path} //= [];
        push $x_to_procs_hr->{$path}->@*, $pid;
    }
    return sort keys(%$x_to_procs_hr);
}

=head2 get_files_for_pid

Essentially the reverse case of lsof_formatted_pids, though doesn't include cwd.

Accepts argument to indicate what PID you want open fds for and optionally
a hashref for us to stuff the data into. The latter was done to simplify
this module's internal caching mechanism and probably doesn't need to be
used by external callers.

Returns LIST of files/sockets/pipes.

=cut

sub get_files_for_pid ( $pid, $x_to_procs_hr = {} ) {
    return _get_x_for_pid( 'fd', $pid, $x_to_procs_hr );
}

=head2 get_cwd_for_pid

Accepts argument to indicate what PID you want the cwd for and optionally
a hashref for us to stuff the data into.

Returns cwd for the pid.

=cut

sub get_cwd_for_pid ( $pid, $x_to_procs_hr = {} ) {
    return ( _get_x_for_pid( 'cwd', $pid, $x_to_procs_hr ) )[0];
}

=head2 get_rtd_for_pid

Same as above, just for the process' root directory.
If the result isn't '/', you are probably safe to assume the pid is chrooted
as far as your execution context is concerned.

=cut

sub get_rtd_for_pid ( $pid, $x_to_procs_hr = {} ) {
    return ( _get_x_for_pid( 'root', $pid, $x_to_procs_hr ) )[0];
}

=head2 get_txt_for_pid

Same as get_cwd_for_pid, just for the process' exe directory.
Don't ask me why lsof's human readable output calls this 'txt' instead of 'exe'
Ultimately is just the path to the program.

=cut

sub get_txt_for_pid ( $pid, $x_to_procs_hr = {} ) {
    return ( _get_x_for_pid( 'exe', $pid, $x_to_procs_hr ) )[0];
}

=head2 get_txt_for_pid

This sub delivers, similar data to all the other get_*_for_pid subroutines,
only this time for files loaded by the process into memory.
For those following along in /proc, this is based on the contents of
/proc/$PID/maps, which ultimately is reported in lsof as 'mem' type entries.

=cut

# A bit of duplication here, but we're doing something different ultimately
# in this check.
sub get_mem_for_pid ( $pid, $x_to_procs_hr = {} ) {
    length $pid or return;
    return unless $pid =~ m{^[0-9]+$};
    return if ( $pid <= RESERVED_PIDS );
    my $dir2check = "/proc/$pid/maps";
    local $@;
    my @lines;
    eval { @lines = Cpanel::Slurper::read_lines($dir2check) };
    return if $@ || !@lines;

    # Entries we want look like:
    # 7f1a18bc4000-7f1a18bc5000 rw-p 000d9000 fd:04 439 /usr/lib64/libm.so.6
    # Unfortunately there's lots of dupes, so dedupe it before pushing.
    my %seen;
    foreach my $line (@lines) {
        my @entries = split( /\s+/, $line, 6 );
        next unless $entries[5] && index( $entries[5], '/' ) == 0;
        my $path = $entries[5];
        next if $seen{$path};
        $seen{$path} = 1;
        $x_to_procs_hr->{$path} //= [];
        push $x_to_procs_hr->{$path}->@*, $pid;
    }
    return sort keys(%$x_to_procs_hr);
}

=head2 get_pids_using_file

The opposite case of get_files_for_pid.

Accepts argument to indicate what file/socket/pipe you want PIDs for.

Returns LIST of PIDs.

=cut

sub get_pids_using_file ( $file = '' ) {
    length $file or return;
    my $file_to_pid = open_files();
    ref $file_to_pid eq 'HASH' or return;

    # Dirs don't get indexed with trailing slash(es), so "correct" that
    # for the caller if they make that mistake.
    $file =~ s{/+$}{};
    return unless length $file;
    ref $file_to_pid->{$file} eq 'ARRAY' or return;

    return $file_to_pid->{$file}->@*;
}

sub _get_pids_using_x_inode ( $inode = '', $x = '' ) {
    length $inode or return;
    return get_pids_using_file("$x:[$inode]");
}

=head2 get_pids_using_socket_inode

Convenience method so that you don't have to remember to pass something like
'socket[1234]' to get_pids_using file (and can instead just pass the inode that
would otherwise be in brackets there.

Accepts argument to indicate what socket inode you want PIDs for.

Returns LIST of PIDs.

=cut

sub get_pids_using_socket_inode ( $inode = '' ) {
    return _get_pids_using_x_inode( $inode, 'socket' );
}

=head2 get_pids_using_pipe_inode

Same story as get_pids_using_socket_inode, just for pipes instead. Currently
there are no callers for this, but since it was easy to accomodate, I figured
I may as well throw it in for completeness' sake.

Accepts argument to indicate what pipe inode you want PIDs for.

Returns LIST of PIDs.

=cut

sub get_pids_using_pipe_inode ( $inode = '' ) {
    return _get_pids_using_x_inode( $inode, 'pipe' );
}

1;
