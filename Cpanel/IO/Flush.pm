package Cpanel::IO::Flush;

# cpanel - Cpanel/IO/Flush.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::IO::Flush

=head1 SYNOPSIS

    Cpanel::IO::Flush::write_all( \*STDOUT, 5, 'data to be written' );

=head1 DESCRIPTION

This module is useful for imitating blocking behavior on a non-blocking
filehandle.

=cut

use constant {
    _EAGAIN => 11,
    _EINTR  => 4,
};

use Cpanel::Exception ();
use IO::SigGuard      ();

=head1 FUNCTIONS

=head2 write_all( FILEHANDLE, TIMEOUT, PAYLOAD )

Writes out the entirety of PAYLOAD. If a write is incomplete, then we
keep trying until the entire PAYLOAD has been sent.

TIMEOUT is in seconds, and PAYLOAD is a plain octet string.

=cut

sub write_all {    ##no critic qw( RequireArgUnpacking )
    my ( $fh, $timeout ) = @_;    # $_[2] = payload

    local ( $!, $^E );

    my $offset = 0;

    {
        my $this_time = IO::SigGuard::syswrite( $fh, $_[2], length( $_[2] ), $offset );
        if ($this_time) {
            $offset += $this_time;
        }
        elsif ( $! == _EAGAIN() ) {
            _wait_until_ready( $fh, $timeout );
        }
        else {
            die Cpanel::Exception::create( 'IO::WriteError', [ error => $!, length => length( $_[2] ) - $offset ] );
        }

        redo if $offset < length( $_[2] );
    }

    return;
}

sub _wait_until_ready {
    my ( $fh, $timeout ) = @_;

    my $win;
    vec( $win, fileno($fh), 1 ) = 1;

    my $ready = select( undef, my $wout = $win, undef, $timeout );

    if ( $ready == -1 ) {
        redo if $! == _EINTR();
        die Cpanel::Exception::create( 'IO::SelectError', [ error => $! ] );
    }
    elsif ( !$ready ) {

        #This should be rare enough that there’s no need to translate it.
        die Cpanel::Exception::create_raw( 'Timeout', 'write timeout!' );
    }

    return;
}

1;
