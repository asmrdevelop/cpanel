package Cpanel::Fuser;

# cpanel - Cpanel/Fuser.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Fuser

=head1 DESCRIPTION

Determines if a list of files are in use by another process.

=head1 SYNOPSIS

    my $used = Cpanel::Fuser::check( @files );

=head1 Subroutines

=head2 check(@files)

Pass a list of files and you'll be returned a hash of what files have them open.
because a hash not a hash ref is returned, this can also be used in a boolean
context.

=cut

use cPstrict;

sub check (@files) {
    my @procs = running_processes();

    my %fuser_data;
    foreach my $pid ( sort @procs ) {
        my @open_files = proc_has_open_files( $pid, @files ) or next;
        foreach my $file (@open_files) {
            $fuser_data{$file} ||= [];
            push $fuser_data{$file}->@*, $pid;
        }
    }
    return %fuser_data;
}

=head2 running_processes()

Returns the list of running pids at the time of call. This is done by checking /proc

=cut

sub running_processes () {
    opendir( my $fh, '/proc' ) or return;
    return grep { m{^[0-9]+$} } readdir $fh;
}

=head2 proc_has_open_files($pid, @files_to_find)

Pass a $pid and a list of files and which files are open by that process will
be returned as an array.

=cut

sub proc_has_open_files ( $pid, @files_to_find ) {

    opendir( my $dfh, "/proc/$pid/fd" ) or return;
    my @fds = grep { m{^[0-9]+$} } readdir $dfh;
    my %files_found;
    foreach my $fd (@fds) {
        my $file_open = readlink("/proc/$pid/fd/$fd") or next;
        $files_found{$file_open}++ if grep { $file_open eq $_ } @files_to_find;
    }

    my @files = sort keys %files_found;

    return @files;
}

1;
