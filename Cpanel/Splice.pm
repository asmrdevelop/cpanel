package Cpanel::Splice;

# cpanel - Cpanel/Splice.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Use this module to make kernel “splice” calls, with fallback logic
# for cases (e.g., old kernels, VZFS) where “splice” won’t work.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Kernel     ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Cpanel::Syscall    ();

#http://lxr.free-electrons.com/source/include/linux/splice.h#L16
our $MOVE     = 0x01;
our $NONBLOCK = 0x02;
our $MORE     = 0x04;
our $GIFT     = 0x08;

my $READ_CHUNK = 65_536;

# http://blog.superpat.com/2010/06/01/zero-copy-in-linux-with-sendfile-and-splice/
# 2.6.31 hangs if you ask for all the data at once
my $MINIMUM_KERNEL_FOR_SPLICE = '2.6.32';

my $MINIMUM_KERNEL_FOR_MODIFYING_PIPE_BUFFER = '2.6.35';

#exposed for testing
our $_copy_via_syscall_works;

#NOTE: As of kernel 2.6.32 there doesn’t seem to be a significant advantage
#to using this function for file-to-file sendfile or splice calls in lieu
#of sysread/syswrite; it may even be slower.
#
sub copy {
    my ( $src_fh, $dest_fh, $length ) = @_;

    if ( !defined $_copy_via_syscall_works ) {
        $_copy_via_syscall_works = 0 if !_kernel_might_support_splice();
    }

    if ( $_copy_via_syscall_works || !defined $_copy_via_syscall_works ) {
        my $func_cr;

        my $src_fd = fileno $src_fh  or die $!;
        my $dst_fd = fileno $dest_fh or die $!;

        try {

            #If one of the filehandles is already a pipe,
            #then we can just do a simple splice call.
            if ( -p $src_fh || -p $dest_fh ) {
                $func_cr = \&_simple_splice;
            }

            #No, huh? Filehandles are to real files? <sigh> Fine.
            else {
                $func_cr = \&_copy_files_via_syscall;
            }

            $func_cr->(
                $src_fd,
                $dst_fd,
                $length,
            );
            $_copy_via_syscall_works = 1;
        }
        catch \&_handle_splice_exception;
    }

    if ( !$_copy_via_syscall_works ) {
        _copy_via_read_write( $src_fh, $dest_fh, $length );
    }

    return 1;
}

#NOTE: Input is file descriptors, not Perl file handles. (This is for speed.)
#Return value is what splice returns.
#
#This *only* knows how to splice(). If splice() is unsupported, you’ll get
#a special Cpanel::Exception::SystemCall::Unsupported error.
#
sub splice_one_chunk {
    my ( $src_fd, $dst_fd, $length ) = @_;

    $length ||= $READ_CHUNK;

    my $bytes_copied;

    if ($_copy_via_syscall_works) {
        $bytes_copied = _splice( $src_fd, $dst_fd, $length );
    }
    elsif ( !defined $_copy_via_syscall_works ) {
        if ( _kernel_might_support_splice() ) {
            try {
                $bytes_copied            = _splice( $src_fd, $dst_fd, $length );
                $_copy_via_syscall_works = 1;
            }
            catch \&_handle_splice_exception;
        }
        else {
            $_copy_via_syscall_works = 0;
        }

        if ( !$_copy_via_syscall_works ) {
            die Cpanel::Exception::create( 'SystemCall::Unsupported', [ name => 'splice' ] );
        }
    }

    return $bytes_copied;
}

sub _kernel_might_support_splice {
    return Cpanel::Kernel::system_is_at_least($MINIMUM_KERNEL_FOR_SPLICE);
}

sub _handle_splice_exception {
    local $@ = $_;

    #If we got here because the system call
    #is unavailable, then retry using ordinary read/write.
    #Otherwise, fail.
    #
    die if !try { $_->error_name() eq 'EINVAL' };

    $_copy_via_syscall_works = 0;

    return;
}

sub _simple_splice {
    my ( $src_fd, $dst_fd, $length ) = @_;

    my $bytes_left = $length;

    #This loop should only go through once unless the first splice
    #does a partial read for some reason.
    while ($bytes_left) {
        $bytes_left -= _splice(
            $src_fd,
            $dst_fd,
            $bytes_left,
            $Cpanel::Splice::MOVE,
        );
    }

    return 1;
}

my $pipe_max_size;

#NOTE: Unused, but it’s in here for potential future use. See below.
sub _copy_files_via_syscall {
    my ( $src_fd, $dst_fd, $length ) = @_;

    #“splice” requires that at least one of the file handles
    #be a pipe, so we have to have two “splice” calls: one to read
    #from the source file into the pipe, and the other to read
    #from the pipe into the destination file.

    #NOTE: Kernel 2.6.33 and beyond allow the “sendfile” system call to
    #work file-to-file. From testing on CentOS 7, though, that doesn’t
    #seem any more effective than “splice”, which itself actually seems
    #*less* effective than read/write.
    #
    #For future testing, the “sendfile” version of this function is:
    #
    #return Cpanel::Syscall::syscall(
    #   'sendfile',
    #   $dst_fd,
    #   $src_fd,
    #   0,
    #   $length,
    #);

    pipe( my $rdr, my $wtr ) or die "pipe(): $!";
    my $rdr_fd = fileno $rdr;
    my $wtr_fd = fileno $wtr;

    #Kernel 2.6.35 allows setting the pipe buffer size.
    #(Even that, in CentOS 7, made no real difference.)
    if ( Cpanel::Kernel::system_is_at_least($MINIMUM_KERNEL_FOR_MODIFYING_PIPE_BUFFER) ) {

        #Linux: include/uapi/asm-generic/fcntl.h
        my $F_LINUX_SPECIFIC_BASE = 1024;

        #Linux: include/uapi/linux/fcntl.h
        my $F_SETPIPE_SZ = $F_LINUX_SPECIFIC_BASE + 7;

        #None of the following is necessary; it’s just optimization at best.
        #It also seems to fail sporadically for unknown reasons.
        try {
            $pipe_max_size ||= do {
                Cpanel::LoadModule::load_perl_module('Cpanel::LoadFile');
                my $s = Cpanel::LoadFile::load('/proc/sys/fs/pipe-max-size');
                chomp $s;
                $s;
            };

            for my $fd ( $rdr_fd, $wtr_fd ) {
                Cpanel::Syscall::syscall(
                    'fcntl',
                    $fd,
                    $F_SETPIPE_SZ,
                    0 + $pipe_max_size,
                );
            }
        }
        catch {
            local $@ = $_;
            warn;
        };
    }

    my $bytes_left = $length;

    #This loop should only go through once unless the first splice
    #does a partial read for some reason.
    while ($bytes_left) {
        my $bytes_read = _splice(
            $src_fd,
            $wtr_fd,
            $bytes_left,
            $Cpanel::Splice::MOVE,
        );

        $bytes_left -= $bytes_read;

        #Just in case, for whatever reason, the write-out splice
        #doesn’t write out the entire contents of the pipe.
        while ($bytes_read) {
            $bytes_read -= _splice(
                $rdr_fd,
                $dst_fd,
                $bytes_read,
                $Cpanel::Splice::MOVE,
            );
        }
    }

    return 1;
}

sub _copy_via_read_write {
    my ( $src_fh, $dest_fh, $bytes_left ) = @_;

    my ( $buffer, $this_time );

    require Cpanel::Autodie;

  READ:
    while (1) {
        $this_time = ( $READ_CHUNK > $bytes_left ) ? $bytes_left : $READ_CHUNK;
        $this_time = Cpanel::Autodie::sysread_sigguard( $src_fh, $buffer, $this_time );
        last READ if !$this_time;
        $bytes_left -= $this_time;
        Cpanel::Autodie::syswrite_sigguard( $dest_fh, $buffer );
    }

    return 1;
}

#
# Arguments
#   in_fd
#   out_fd
#   length
#   flags (optional)
#
# You cannot use this function without providing a backup for when splice
# returns EINVAL.  splice does not work on some file systems (e.g. VZFS).
sub _splice {    # -- this is a system call
    return Cpanel::Syscall::syscall(
        'splice',
        $_[0] + 0,
        0,
        $_[1] + 0,
        0,
        $_[2] + 0,
        $_[3] || 0,
    );
}

1;
