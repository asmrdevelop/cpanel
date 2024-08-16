package Cpanel::FHUtils;

# cpanel - Cpanel/FHUtils.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# BE LEAN: avoid use()
# This module gets included in exim.pl.local

use Cpanel::Fcntl::Constants  ();
use Cpanel::Finally           ();
use Cpanel::FHUtils::Tiny     ();
use Cpanel::FHUtils::Blocking ();

*are_same         = *Cpanel::FHUtils::Tiny::are_same;
*to_bitmask       = *Cpanel::FHUtils::Tiny::to_bitmask;
*set_non_blocking = *Cpanel::FHUtils::Blocking::set_non_blocking;
*set_blocking     = *Cpanel::FHUtils::Blocking::set_blocking;
*is_set_to_block  = *Cpanel::FHUtils::Blocking::is_set_to_block;
*_get_fl_flags    = *Cpanel::FHUtils::Blocking::_get_fl_flags;

#NOTE: The read/write status of a file handle is a bit weird to read
#from the fcntl(F_GETFL) response. The lowest bit indicates write-only,
#and the next-lowest bit indicates read/write.

sub is_reader {
    my ($fh) = @_;
    return ( _get_io_mode_of_fh($fh) != $Cpanel::Fcntl::Constants::O_WRONLY ) ? 1 : 0;
}

sub is_writer {
    my ($fh) = @_;
    return ( _get_io_mode_of_fh($fh) != $Cpanel::Fcntl::Constants::O_RDONLY ) ? 1 : 0;
}

sub is_reader_and_writer {
    my ($fh) = @_;
    return ( _get_io_mode_of_fh($fh) == $Cpanel::Fcntl::Constants::O_RDWR ) ? 1 : 0;
}

#Returns the contents of the buffer.
#
#NOTE: This is pretty "iffy" logic. Rather than use this, please consider
#whether your problem can be solved by not commingling buffered and
#unbuffered I/O.
#
sub flush_read_buffer {
    my ($fh) = @_;

    #A file handle to a regular file will be slurped in its entirety
    #if passed in. If this is ever useful, then just remove the below,
    #but as of this writing this function is only useful for pipes,
    #STDIN, and sockets.
    if ( -f $fh ) {
        die "This doesn't work (yet?) with a regular file.";
    }

    if ( !is_reader($fh) ) {
        die "flush_read_buffer can only flush a file handle that is open for reading";
    }

    no warnings 'io';    # perl 5.22 will tell us that STDERR is readable when it is not

    my $finally;
    if ( is_set_to_block($fh) ) {
        $finally = Cpanel::Finally->new( sub { set_blocking($fh) } );
        set_non_blocking($fh);
    }

    my $buffer = q<>;

    local ( $!, $^E );
    while ( !$! ) {
        last if !read $fh, $buffer, 512, length $buffer;
        1;
    }

    return $buffer;
}

#----------------------------------------------------------------------

*get_io_mode_of_fh = *_get_io_mode_of_fh;

sub _get_io_mode_of_fh {
    my ($fh) = @_;

    return _get_fl_flags($fh) & $Cpanel::Fcntl::Constants::O_ACCMODE;
}

1;
