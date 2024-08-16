package Cpanel::Streamer::TarBackup;

# cpanel - Cpanel/Streamer/TarBackup.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::TarBackup

=head1 DESCRIPTION

A streamer module for creating and sending a L<tar(1)> archive.

=head1 INTERFACE

See L<Cpanel::Streamer::Base::Tar> for details that pertain to all
subclasses of that class.

=head2 I/O

The input stream is ignored.

The output stream is C<tar>’s STDOUT.

STDERR is untouched; i.e., it’ll go wherever the parent process’s STDERR
goes.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Streamer::Base::Tar';

use constant _REQUIRED_PARAMETERS => ('paths');

#----------------------------------------------------------------------

sub _prepare_std_filehandles ( $, $child_s ) {
    open \*STDIN, '>', '/dev/null' or do {
        die "Failed to set STDIN to /dev/null: $!";
    };

    open \*STDOUT, '>>&=', $child_s or do {
        die "Failed to set STDOUT to socket: $!";
    };

    return;
}

sub _tar_parameters ( $, $opts_hr ) {
    return (
        '--create',
        '--file', '-',
        @{ $opts_hr->{'paths'} },
    );
}

1;
