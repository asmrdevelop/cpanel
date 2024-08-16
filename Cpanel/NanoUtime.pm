package Cpanel::NanoUtime;

# cpanel - Cpanel/NanoUtime.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::NanoUtime - fractional-second C<utime()>

=head1 SYNOPSIS

    # Only accepts a path!
    Cpanel::NanoUtime::utime( $atime, $mtime, $path ) or do { ... };

    # Only accepts a Perl filehandle or file descriptor.
    Cpanel::NanoUtime::futime( $atime, $mtime, $fh_or_fd ) or do { ... };

=head1 DESCRIPTION

This implements logic equivalent to L<Time::HiRes>’s C<utime()>.

To find corresponding C<stat()> logic, see L<Cpanel::NanoStat>.

=cut

#----------------------------------------------------------------------

use Cpanel::Struct::timespec ();

use constant {
    _NR_utimensat => 280,

    _AT_FDCWD            => -100,
    _AT_SYMLINK_NOFOLLOW => 0x100,
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 utime( $ATIME, $MTIME, $PATH )

Sets $PATH’s atime and mtime. If $PATH is a symbolic link, then the
link’s target will be updated.

=cut

sub utime {
    return _syscall( 0 + _AT_FDCWD(), $_[2], @_[ 0, 1 ], 0 );
}

=head2 futime( $ATIME, $MTIME, $FH_OR_FD )

Like C<utime()> but accepts either a Perl filehandle or file descriptor.

=cut

sub futime {
    return _syscall(
        0 + ( ref( $_[2] ) ? fileno( $_[2] ) : $_[2] ),
        undef,
        @_[ 0, 1 ],
        0,
    );
}

=head2 lutime( $ATIME, $MTIME, $PATH )

Like C<utime()>, but if $PATH is a symbolic link, then the link’s own
atime and mtime will be updated.

=cut

sub lutime {
    return _syscall( 0 + _AT_FDCWD(), $_[2], @_[ 0, 1 ], 0 + _AT_SYMLINK_NOFOLLOW() );
}

my ( $path, $buf ) = @_;

sub _syscall {

    if ( defined $_[-3] ) {
        if ( defined $_[-2] ) {
            $buf = Cpanel::Struct::timespec->float_to_binary( $_[-3] ) . Cpanel::Struct::timespec->float_to_binary( $_[-2] );
        }
        else {
            die "atime is “$_[-3]”, but mtime is undef!";
        }
    }
    elsif ( defined $_[-2] ) {
        die "atime is undef, but mtime is “$_[-2]”!";
    }
    else {
        $buf = undef;
    }

    # Duplicate so that static paths don’t cause breakage.
    $path = $_[1];

    # If the value is undef then Perl expects that we pass a literal. (??)
    return undef if -1 == syscall( 0 + _NR_utimensat(), $_[0], $path // undef, $buf // undef, $_[-1] );

    return 1;
}

1;
