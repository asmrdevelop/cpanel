package Cpanel::Services::Hot;

# cpanel - Cpanel/Services/Hot.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf8

=head1 NAME

Cpanel::Services::Hot - Utility support functions for hot restartable services

=head1 SYNOPSIS

    use Cpanel::Services::Hot ();

=head1 DESCRIPTION

L<Cpanel::Services::Hot> provides utility support functions for services that
can be hot restarted, i.e., restarted with a simple exec() over the existing
process image.

=cut

my $pid_file_fh;

=head1 FUNCTIONS

=over

=item C<make_pid_file(I<$pid_file>)>

Create a file called I<$pid_file> whose sole contents are the ID of the current
process, with no newline appended.  The file descriptor referring to
I<$pid_file> shall be left open, which is useful for verifying that the PID
file is indeed owned by a current, living process and that said process is
indeed responsible for the PID file.

=cut

sub make_pid_file {
    my ( $pid_file, $pid ) = @_;

    $pid = $$ unless defined $pid;

    # We want to keep the pid file handle open for the duration of the process,
    # so that bin/needs-restarting-cpanel can verify that the pid listed in any
    # given pid file refers to a current and running process, and that said
    # process still retains an open file handle for the pid file in question.
    # This linkage, plus the mtime of the pidfile, can be used to determine if
    # a hot restartable service has been restarted with the same pid.

    if ( defined $pid_file_fh ) {
        close $pid_file_fh;
        undef $pid_file_fh;
    }

    my $pid_file_tmp = "$pid_file.$$";

    open( $pid_file_fh, '>', $pid_file_tmp ) or goto error_io;

    chmod( 0644, $pid_file_fh ) or goto error_io;

    syswrite( $pid_file_fh, $$ ) or goto error_io;

    rename( $pid_file_tmp => $pid_file ) or goto error_io;

    return 1;

  error_io:
    if ( defined $pid_file_fh ) {
        close $pid_file_fh;
        undef $pid_file_fh;
    }

    return 0;
}

=item C<get_pid_from_file(I<$pid_file>)>

Returns the PID contained within I<$pid_file>.  Any trailing whitespace will
be chomp()ed.  Returns nothing if I<$pid_file> cannot be opened, or will return
undef if the file is empty.

=cut

sub get_pid_from_file {
    my ($pid_file) = @_;

    open my $fh, '<', $pid_file or return;

    my $pid = readline $fh;

    close $fh;

    chomp $pid if $pid;

    return $pid;
}

=item C<is_pid_running(I<$pid>)>

Returns true if a process numbered I<$pid> is currently running, otherwise
false.

=cut

sub is_pid_running {
    my ($pid) = @_;

    return -d "/proc/$pid";
}

=item C<is_pid_file_active(I<$pid_file>)>

Returns true if I<$pid_file> refers to a currently running process which also
holds a current file descriptor for I<$pid_file>, otherwise false.

=cut

sub is_pid_file_active {
    my ($pid_file) = @_;

    my @st  = stat $pid_file               or return 0;
    my $pid = get_pid_from_file($pid_file) or return 0;

    my $pid_fd_dir = "/proc/$pid/fd";

    opendir my $dh, $pid_fd_dir or return 0;

    while ( defined( my $dirent = readdir $dh ) ) {
        next if $dirent eq '.' || $dirent eq '..';

        my $path = "$pid_fd_dir/$dirent";
        my $dest = readlink $path or next;

        # Continue if the symlink destination for this /proc/$pid/fd entry does
        # not obviously look like a PID file.
        next unless $dest =~ /\.pid$/;

        my @dest_st = stat $dest or next;

        # If the file held by the current /proc/$pid/fd file descriptor entry
        # has the same device and inode number as the PID file we currently
        # hold, then consider this a match; indeed, $pid_file does refer to a
        # running and active process which holds said PID file open.
        if ( $st[0] == $dest_st[0] && $st[1] == $dest_st[1] ) {
            closedir $dh;

            return $pid;
        }
    }

    closedir $dh;

    return 0;
}

=item C<is_pid_file_self_or_dead(I<$pid_file>)>

Returns true if I<$pid_file> refers to a PID file for the current process, or
if the process referred to by I<$pid_file> is not running.

=cut

sub is_pid_file_self_or_dead {
    my ($pid_file) = @_;

    if ( my $pid = get_pid_from_file($pid_file) ) {
        if ( $pid == $$ || !is_pid_running($pid) ) {
            return 1;
        }
    }

    return 0;
}

=back

=head1 COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C.  All rights reserved.

=cut

1;
