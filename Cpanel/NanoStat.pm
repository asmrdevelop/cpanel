package Cpanel::NanoStat;

# cpanel - Cpanel/NanoStat.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::NanoStat - fractional-second precision stat() functions

=head1 SYNOPSIS

    # Only takes a path!
    @stat = Cpanel::NanoStat::stat($path);

    # Only takes a filehandle or file descriptor.
    @stat = Cpanel::NanoStat::fstat($fh_or_fd);

    @stat = Cpanel::NanoStat::lstat($path);

=head1 DESCRIPTION

This module exposes functionality that mimics the C<stat()> and
C<lstat()> functions in Time::HiRes.

To find corresponding C<utime()> logic, see L<Cpanel::NanoUtime>.

=cut

use Cpanel::Struct::timespec ();

use constant {
    _NR_stat  => 4,
    _NR_fstat => 5,
    _NR_lstat => 6,
};

use constant _PACK_TEMPLATE => q<
    Q       # st_dev
    Q       # st_ino

    # Reverse these two to match Perl’s stat().
    # (Curiously, “man 2 stat” documents these in reverse order!)
    @24 L   # st_mode
    @16 Q   # st_nlink

    @28
    L       # st_uid
    L       # st_gid

    x![Q]
    Q       # st_rdev
    Q       # st_size
    Q       # st_blksize
    Q       # st_blocks
>;

my $pre_times_pack_len = length pack _PACK_TEMPLATE();

# This is the length of struct stat.
# The template above is 72 bytes, and the three timespecs
# for atime/mtime/ctime are 3 * 16 = 48. That’s 120 bytes total;
# the other 24 aren’t documented for any purpose.
my $buf = ( "\0" x 144 );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @nums = stat( $PATH )

Mimics L<Time::HiRes>’s function of the same name but does B<NOT>
accept a filehandle! For that you need C<fstat()>.

=cut

sub stat {
    return _syscall( _NR_stat(), $_[0] );
}

=head2 @nums = fstat( $FH_OR_FD )

Like C<stat()>, but this accepts a Perl filehandle or a file descriptor
instead of a path.

=cut

sub lstat {
    return _syscall( _NR_lstat(), $_[0] );
}

=head2 @nums = lstat( $PATH )

Mimics L<Time::HiRes>’s function of the same name.

=cut

sub fstat {
    return _syscall( _NR_fstat(), 0 + ( ref( $_[0] ) ? fileno( $_[0] ) : $_[0] ) );
}

#----------------------------------------------------------------------

sub _syscall {    ## no critic qw(RequireArgUnpacking)
    my $arg_dupe = $_[1];
    return undef if -1 == syscall( $_[0], $arg_dupe, $buf );
    my @vals = unpack _PACK_TEMPLATE(), $buf;
    splice(
        @vals, 8, 0,
        @{ Cpanel::Struct::timespec->binaries_to_floats_at( $buf, 3, $pre_times_pack_len ) },
    );

    return @vals;
}

1;
