package Cpanel::IO::Tarball;

# cpanel - Cpanel/IO/Tarball.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Proc::FastSpawn ();

use Cpanel::Autodie               ();
use Cpanel::Splice                ();
use Cpanel::Syscall               ();
use Cpanel::ForkAsync             ();
use Cpanel::IO::Mux               ();
use Cpanel::Gzip::Config          ();
use Cpanel::ChildErrorStringifier ();
use Cpanel::Waitpid               ();

#manipulated in tests
our $_WE_CAN_USE_SPLICE;

our $LENGTH_OF_ERR_TO_READ_ONE_LOOP = 512;

=encoding utf-8

=head1 NAME

Cpanel::IO::Tarball - Create a compressed tarball stream

=head1 DESCRIPTION

C<Cpanel::IO::Tarball> provides a very simple means of producing compressed tar
streams, while accurately catching and reporting errors from either the tar or
gzip subprocess spawned to perform this task.

=head1 CREATING A NEW TARBALL STREAM

=over

=item C<Cpanel::IO::Tarball-E<gt>new(%args)>

Create a new compressed tarball stream.  The following argument should be passed
when invoking this method.

=over

=item C<tar_writer>

A I<CODE> reference which accepts a Perl file handle to write tar data to.

Example:

    my $tarball = Cpanel::IO::Tarball->new(
        'tar_writer' => sub {
            my ($handle) = @_;

            tar($handle,  './foo/bar', './baz');
        }
    );

=item C<output_stream_fh> (optional)

A I<GLOB> reference write tar data to (or compressed tar data if compress is enabled).

If this argument is not passed, calls to splice must pass a fd each time

Example:

    my $tarball = Cpanel::IO::Tarball->new(
        'output_stream_fh' => $fh_to_tar_file,
        'compress' => 0,
        'tar_writer' => sub {
            my ($handle) = @_;

            tar($handle,  './foo/bar', './baz');
        }
    );

=back

=back

=cut

sub new {
    my ( $class, %args ) = @_;

    unless ( $args{'tar_writer'} ) {
        die('No tarball writer passed in "tar_writer"');
    }

    unless ( ref( $args{'tar_writer'} ) eq 'CODE' ) {
        die('Tarball writer passed in "tar_writer" is not a CODE ref');
    }

    my $output_stream_fh = $args{'output_stream_fh'};
    my $gzip_config      = $args{'gzip_config'} ? $args{'gzip_config'} : Cpanel::Gzip::Config->load;
    my @gzip_command     = $gzip_config->command();
    my $compress         = 1;

    if ( defined $args{'compress'} && !$args{'compress'} ) {
        $compress = 0;
    }
    my $mux = Cpanel::IO::Mux->new( 'timeout' => 30 );

    my $tar_pid;
    my ( $tarball_in, $tarball_out, $opened_tarball_in );
    if ( $output_stream_fh && !$compress ) {
        $tarball_in = $output_stream_fh;
    }
    else {
        $opened_tarball_in = 1;
        pipe( $tarball_out, $tarball_in ) or die("Unable to pipe(): $!");
    }

    my ( $tar_err_out, $tar_err_in );
    {
        pipe( $tar_err_out, $tar_err_in ) or die("Unable to pipe(): $!");
        $tar_pid = Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::Autodie::close($tar_err_out);
                Cpanel::Autodie::close($tarball_out);
                local $0 = "$0 - create tar stream";

                open( STDERR, '>&=' . fileno($tar_err_in) ) or die("Unable to redirect stderr: $!");    ## no critic(ProhibitTwoArgOpen) - Needed to redirect file handle on Perl 5.6 without needing POSIX::dup2()
                $args{'tar_writer'}->($tarball_in);
            }
        );

        Cpanel::Autodie::close($tar_err_in);
        Cpanel::Autodie::close($tarball_in) if $opened_tarball_in;
        $mux->set( $tar_err_out, 'read' );
        if ( !$compress && !$output_stream_fh ) {
            $output_stream_fh = $tarball_out;
            $mux->set( $output_stream_fh, 'read' );
        }
    }

    my ( $gzip_pid, $gzip_err_out, $gzip_err_in );
    if ($compress) {
        -x $gzip_config->{'bin'} or die("Gzip utility ($gzip_config->{'bin'}) not available");

        pipe( $gzip_err_out, $gzip_err_in ) or die("Unable to pipe(): $!");

        my ( $gzip_in, $gzip_out, $opened_gzip_in );
        if ($output_stream_fh) {
            $gzip_in = $output_stream_fh;
        }
        else {
            pipe( $gzip_out, $gzip_in ) or die("Unable to pipe(): $!");
            $opened_gzip_in = 1;
        }

        $gzip_pid = Proc::FastSpawn::spawn_open3(
            fileno($tarball_out),    # stdin,
            fileno($gzip_in),        # stdout
            fileno($gzip_err_in),    # stderr
            $gzip_command[0],        # program
            \@gzip_command,          # args
        );

        Cpanel::Autodie::close($gzip_err_in);
        Cpanel::Autodie::close($gzip_in) if $opened_gzip_in;
        $mux->set( $gzip_err_out, 'read' );
        if ( !$output_stream_fh ) {
            $output_stream_fh = $gzip_out;
            $mux->set( $output_stream_fh, 'read' );
        }
    }

    return bless {
        'tar_pid'            => $tar_pid,
        'tar_err'            => $tar_err_out,
        'tar_err_fileno'     => fileno($tar_err_out),
        'tar_messages'       => '',
        'gzip_config'        => $gzip_config,
        'gzip_command'       => \@gzip_command,
        'gzip_pid'           => $gzip_pid,
        'tarball_out'        => $output_stream_fh,
        'tarball_out_fileno' => fileno($output_stream_fh),
        'gzip_err'           => $gzip_err_out,
        'gzip_err_fileno'    => $gzip_err_out ? fileno($gzip_err_out) : undef,
        'gzip_messages'      => '',
        'mux'                => $mux
    }, $class;
}

=head1 SPLICING THE TAR STREAM TO A FILE DESCRIPTOR

=over

=item C<$readlen = $tarball-E<gt>splice($out_fd, $len)>

Read C<$len> bytes and send it to the file handle with descriptor C<$out_fd>.
The number of bytes actually read is returned in C<$readlen>.

If there are still open file handles in the mux object and the select
times out the splice function will return '0E0' to signal the caller
that while nothing was read, it should continue to splice, check for timeout,
or other tasks as desired.

NOTE: This contains fallback logic in case the system doesn’t actually support
the “splice” system call.

If the object was created with C<output_stream_fh>, C<$out_fd> and C<$len> will
be ignored.

=back

=cut

sub splice {
    my ( $self, $out_fd, $len ) = @_;

    my $readlen;
    while ( my $ready = $self->{'mux'}->select ) {

        #
        # Check each file handle we care about to see if it is in the ready set.
        # If it is in the ready set, but nothing could be read (due to EOF),
        # then drop the handle from future select() calls.
        #

        if ( $out_fd && $ready->is_fileno_set( $self->{'tarball_out_fileno'}, 'read' ) ) {
            if ($_WE_CAN_USE_SPLICE) {
                $readlen = Cpanel::Splice::splice_one_chunk(
                    $self->{'tarball_out_fileno'},
                    $out_fd,
                    $len,
                );
            }
            else {
                if ( !defined $_WE_CAN_USE_SPLICE ) {
                    try {
                        $readlen = Cpanel::Splice::splice_one_chunk(
                            $self->{'tarball_out_fileno'},
                            $out_fd,
                            $len,
                        );
                        $_WE_CAN_USE_SPLICE = 1;
                    }
                    catch {
                        if ( !try { $_->isa('Cpanel::Exception::SystemCall::Unsupported') } ) {
                            local $@ = $_ and die;
                        }
                        $_WE_CAN_USE_SPLICE = 0;
                    };
                }

                if ( !$_WE_CAN_USE_SPLICE ) {
                    $readlen = Cpanel::Autodie::sysread_sigguard( $self->{'tarball_out'}, my $buf, $len );

                    #No try() since we are in a loop.
                    local $@;

                    #Do this rather than syswrite() because we only have the file
                    #descriptor, not Perl’s file handle variable. (It might be nice if
                    #syswrite() accepted a file descriptor in lieu of a file handle...)
                  WRITE:
                    while (1) {
                        last WRITE if eval {
                            Cpanel::Syscall::syscall( 'write', $out_fd, $buf, $readlen );
                            1;
                        };

                        die if !try { $@->error_name() eq 'EINTR' };
                    }
                }
            }

            if ( !$readlen ) {
                $self->{'mux'}->clear( $self->{'tarball_out'}, 'read' );
            }
        }
        if ( $ready->is_fileno_set( $self->{'tar_err_fileno'}, 'read' ) ) {
            if ( Cpanel::Autodie::sysread_sigguard( $self->{'tar_err'}, my $err_buf, $LENGTH_OF_ERR_TO_READ_ONE_LOOP ) ) {
                $self->{'tar_messages'} .= $err_buf;
            }
            else {
                $self->{'mux'}->clear( $self->{'tar_err'}, 'read' );
            }
        }

        if ( defined $self->{'gzip_err'} && $ready->is_fileno_set( $self->{'gzip_err_fileno'}, 'read' ) ) {
            if ( Cpanel::Autodie::sysread_sigguard( $self->{'gzip_err'}, my $err_buf, $LENGTH_OF_ERR_TO_READ_ONE_LOOP ) ) {
                $self->{'gzip_messages'} .= $err_buf;
            }
            else {
                $self->{'mux'}->clear( $self->{'gzip_err'}, 'read' );
            }
        }

        return $readlen if $readlen;
        return '0E0'    if !$self->{'mux'}->_empty();    #timeout, not all clear
    }

    return;
}

sub _reap_and_handle_errors {
    my ( $program, $pid, $messages ) = @_;

    chomp $messages;

    Cpanel::Waitpid::sigsafe_blocking_waitpid( $pid, 0 );
    my $child_error = Cpanel::ChildErrorStringifier->new( $?, $program );

    if ( !$child_error->CHILD_ERROR() ) {
        if ($messages) {

            # This is not a good way to pass messages back to the
            # caller, however refactoring it outside of scope
            $@ = "Warning from $program process $pid: $messages";
        }
        return;
    }

    my $autopsy = $child_error->autopsy();
    if ($messages) {
        die "$autopsy: $messages";
    }

    die $autopsy;
}

=head1 CLOSING THE TARBALL STREAM

=over

=item C<$tarball-E<gt>close()>

Close the tarball stream.  Afterwards, any nonzero exit statuses, or data
written to the tar or gzip stderr file handles is presented to the caller, with
program name, process ID and exit status where appropriate.

=over

=item Zero exit statuses, errors read

The errors captured from the tar and gzip subprocesses will be copied to C<$@>.
The error message and process ID of each process that recorded errors will be
indicated therein.

=item Nonzero exit statuses, errors read

The errors captured from the tar and gzip subprocesses will be raised with a
L<die()|perlfunc/die>.  The exit status and process ID of the first failed
process is indicated in the message.

=item Nonzero exit statuses, no errors read

A nonspecific error is raised with L<die()|perlfunc/die>, indicating the process
name, ID and exit status of the first failed process.

=back

=back

=cut

sub close {
    my ($self) = @_;

    close $self->{'tarball_out'};
    if ( $self->{'gzip_pid'} && $self->{'gzip_err'} ) {
        close $self->{'gzip_err'};
        _reap_and_handle_errors( join( ' ', @{ $self->{'gzip_command'} } ), $self->{'gzip_pid'}, $self->{'gzip_messages'} );
    }
    close $self->{'tar_err'};
    _reap_and_handle_errors( 'Archive::Tar::Builder', $self->{'tar_pid'}, $self->{'tar_messages'} );

    return;
}

1;

__END__

=head1 COPYRIGHT

Copyright (c) 2015, cPanel, inc.  Distributed under the terms of the cPanel
license.  Unauthorized copying is prohibited.
