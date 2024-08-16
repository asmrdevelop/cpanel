package Cpanel::LoadFile::ReadFast;

# cpanel - Cpanel/LoadFile/ReadFast.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LoadFile::ReadFast

=head1 SYNOPSIS

    read_all_fast( $fh, my $buffer );

    read_fast( $fh, my $buffer, $size );

    read_fast( $fh, my $buffer, $size, $offset );

=head1 DESCRIPTION

This module contains useful wrappers around Perl’s C<sysread()> built-in.
They should generally be preferred to that built-in.

=head1 SPEED

For general use, C<read_all_fast()> is probably your best bet. Since that
function will read iteratively in chunks, however, you can still end up with
many C<read()> system calls if your file is much bigger than the chunk size.
This is less efficient than a single, large C<read()> call.

If you’re reading from something that you can C<stat()> to get a file size,
then you might realize a palpable gain by doing this:

    read_fast( $fh, my $buffer, -s $fh );

Of course, that doesn’t work for pipes or sockets.

=head1 ERRORS

This module implements the same replay logic as CPAN’s L<IO::SigGuard|https://metacpan.org/pod/IO::SigGuard> module; see that module for more details.

Any other errors prompt an appropriate exception.

=head1 FUNCTIONS

=cut

# Odd syntax to make upcp.static happy
use constant READ_CHUNK => 1 << 18;    # 262144

use constant _EINTR => 4;

=head2 $bytes = read_fast( FH, BUFFER, SIZE, [OFFSET] )

A drop-in replacement for Perl’s C<sysread()>. Exactly the same
logic as C<IO::SigGuard::sysread()>, but a bit lighter since cPanel
only runs on Linux and so doesn’t need L<Errno>.

Like the C<sysread()> built-in, this does B<NOT> do error-checking
for you; you’ll need to check for errors yourself. If you want
a L<Cpanel::Exception>-throwing equivalent, look to
L<Cpanel::Autodie>.

=cut

#NOTE: Buffered reads work in 8,192-byte chunks, even if you’ve
#asked for more. So, we’ll use unbuffered reads.
#
#For a general-use version of this logic, see Cpanel::Autodie::sysread_sigguard().
#
#NOTE: October 2015 has seen a perl-5-porters thread about optimizing
#Perl’s read() built-in so that it’ll take in larger chunks when asked
#rather than always working in 8,192-byte increments. We’ve yet to see
#what comes of it as of this writing.
#
sub read_fast {
    $_[1] //= q<>;

    #
    # *** If changes are made to this function please be sure to copy it
    # *** to t/Cpanel-LoadFile-ReadFast.t: copied_read_fast
    # *** with sysread changed to _sysread since sysread isn't mockable here
    #
    # TODO: read_fast is intended to be a drop in replacemnet
    # for sysread.
    #
    # We currently always call this with with
    # $_[2] being $Cpanel::LoadFile::READ_CHUNK. If we find in the future
    # that we are always using READ_CHUNK in this call we may want
    # adjust this to avoid having to pass in $Cpanel::LoadFile::READ_CHUNK every
    # time.
    #
    #PerlIO’s buffered read() implements the following logic;
    #i.e., if the read() system call is interrupted before any data
    #is read, it will retry the read. This is generally desirable.
    return ( @_ > 3 ? sysread( $_[0], $_[1], $_[2], $_[3] ) : sysread( $_[0], $_[1], $_[2] ) ) // do {
        goto \&read_fast if $! == _EINTR;
        die "Failed to read data: $!";
    };
}

=head2 $bytes = read_all_fast( FH, BUFFER )

Iteratively slurps all available data from C<FH> into C<BUFFER>.
It’s roughly the equivalent of logic from C<File::Slurp>.

=cut

# $_[0] = $fh;
# $_[1] = $data;
my $_ret;

sub read_all_fast {
    $_[1] //= q<>;

    $_ret = 1;
    while ($_ret) {
        $_ret = sysread( $_[0], $_[1], READ_CHUNK, length $_[1] ) // do {
            redo if $! == _EINTR;
            die "Failed to read data: $!";
        }
    }
    return;
}

1;
