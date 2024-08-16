package Cpanel::HTTP::ReadHeaders;

# cpanel - Cpanel/HTTP/ReadHeaders.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie   ();
use Cpanel::Context   ();
use Cpanel::Exception ();

use constant {

    #16 KiB of headers is probably no good.
    MAX_LENGTH => 16384,

    CRLFx2 => "\x0d\x0a" x 2,
};

=encoding utf-8

=head1 NAME

Cpanel::HTTP::ReadHeaders

=head1 SYNOPSIS

    my ($hdr_txt_sr, $body_sr) = Cpanel::HTTP::ReadHeaders::read($socket);

=head1 FUNCTIONS

=head2 ($hdr_txt_sr, $body_start_sr) = read( FILEHANDLE )

Use this to read raw HTTP headers via unbuffered, non-blocking I/O.

C<$hdr_txt> is a scalar reference to the raw text of the headers, including the final two
CRLFs.

C<$body_start> is a scalar reference to whatever initial part of the body we might have
read along with the end of the headers.

=head1 NOTES

This adopts a slurp-then-read approach rather than doing C<recv()> with
the MSG_PEEK flag. This approach should be a bit faster since
C<recv()>/MSG_PEEK requires an extra copy of the data into userspace.
(I didn’t test that, though.)

=cut

sub read {
    my ($socket) = @_;

    Cpanel::Context::must_be_list();

    my $buf = q<>;

    while ( length($buf) < MAX_LENGTH ) {
        Cpanel::Autodie::sysread_sigguard( $socket, $buf, MAX_LENGTH - length($buf), length($buf) ) or do {
            die Cpanel::Exception::create_raw( 'PeerDoneWriting', "No valid HTTP headers received! ($buf)" );
        };

        my $crlfx2_offset = index( $buf, CRLFx2 );
        if ( $crlfx2_offset != -1 ) {
            my $hdr = substr( $buf, 0, 4 + $crlfx2_offset, q<> );
            return ( \$hdr, \$buf );
        }
    }

    die Cpanel::Exception->create_raw( sprintf( "No valid HTTP headers received after reading %d bytes! (%s …)", length $buf, substr( $buf, 0, 1024 ) ) );
}

1;
