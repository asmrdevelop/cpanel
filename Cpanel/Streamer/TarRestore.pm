package Cpanel::Streamer::TarRestore;

# cpanel - Cpanel/Streamer/TarRestore.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::TarRestore

=head1 DESCRIPTION

A streamer module for restoring a L<tar(1)> archive.
This module subclasses L<Cpanel::Streamer::Base::Tar>.

=head1 INTERFACE

This module will overwrite any existing files that conflict with
the received archive contents.

See the base class’s documentation for more details.

In addition to the base class’ parameters, this module allows for:

=over

=item * C<paths> - An arrayref of paths to provide as the final
arguments to the tar binary. Paths will be assumed to be in the
current working directory.

=back

=head2 I/O

The input stream should be the tar archive to restore.

The output stream combines C<tar>’s STDOUT and STDERR.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Streamer::Base::Tar';

#----------------------------------------------------------------------

sub _tar_parameters ( $class, $opts_hr ) {

    my @paths;
    push @paths, "./$_" for ( $opts_hr->{paths} ? @{ $opts_hr->{paths} } : () );

    return (
        '--extract',
        '--preserve-permissions',
        '--overwrite',

        # Necessary to avoid a case where an 0444 file in the target
        # directory would be unwritable as the user:
        ( $> ? ('--recursive-unlink') : () ),

        '--file' => '-',
        @paths,
    );
}

sub _prepare_std_filehandles ( $class, $child_s ) {
    open \*STDIN, '<&=', $child_s or do {
        die "Failed to set STDIN to socket: $!";
    };

    open \*STDOUT, '>>&=', $child_s or do {
        die "Failed to set STDOUT to socket: $!";
    };

    open \*STDERR, '>>&=', $child_s or do {
        die "Failed to set STDERR to socket: $!";
    };

    return;
}

1;
