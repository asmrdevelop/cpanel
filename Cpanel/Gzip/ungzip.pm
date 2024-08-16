package Cpanel::Gzip::ungzip;

# cpanel - Cpanel/Gzip/ungzip.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Compress::Raw::Zlib ();

use constant GZIP_HEADER_PLUS_CM_DEFLATED => "\x{1f}\x{8b}" . "\x08";

use constant Z_OK         => Compress::Raw::Zlib::Z_OK();
use constant Z_BUF_ERROR  => Compress::Raw::Zlib::Z_BUF_ERROR();
use constant Z_STREAM_END => Compress::Raw::Zlib::Z_STREAM_END();
use constant MAX_WBITS    => Compress::Raw::Zlib::MAX_WBITS();
use constant WANT_GZIP    => Compress::Raw::Zlib::WANT_GZIP();

our $VERSION = 2.0;

sub gunzipmem {
    my $compressed = shift // return;
    my $uncompressed;
    my $compressed_ref = ref $compressed ? $compressed : \$compressed;

    # This function requires returning the uncompressed if not compressed
    return $$compressed_ref if !_is_gziped_data($compressed_ref);

    my ( $obj, $status ) = Compress::Raw::Zlib::Inflate->new(
        AppendOutput => 1,
        LimitOutput  => 1,
        ConsumeInput => 1,
        CRC32        => 1,
        WindowBits   => WANT_GZIP,
    );
    if ( $status != Z_OK ) {
        die "Failed to create zlib inflator (zlib err $status)";
    }

    while (1) {
        my $status = $obj->inflate( $$compressed_ref, $uncompressed );

        if ( $status == Z_STREAM_END || !length $$compressed_ref ) {
            last;
        }
        elsif ( $status == Z_OK || $status == Z_BUF_ERROR ) {    # c.f. http://cpansearch.perl.org/src/PMQS/IO-Compress-2.074/lib/IO/Uncompress/Adapter/Inflate.pm
            next;
        }

        my $msg = "Failed to uncompress gzip: $status";

        #The last 8 bytes are the CRC check and length, respectively.
        #When the CRC check fails, the last 4 bytes are left in the buffer;
        #this is useful, then, for detecting that the error was a CRC check
        #failure.
        if ( 4 == ( length($compressed) || 0 ) ) {
            $msg .= " (CRC error?)";
        }
        else {
            $msg .= sprintf ": %v.02x", $compressed;
        }

        die $msg;
    }

    return $uncompressed;
}

sub _is_gziped_data {
    my ($compressed_ref) = @_;

    return 0 if length $$compressed_ref < 3;

    return 0 == rindex( $$compressed_ref, GZIP_HEADER_PLUS_CM_DEFLATED, 0 );
}

1;
