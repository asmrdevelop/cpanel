package Cpanel::Gzip::gzip;

# cpanel - Cpanel/Gzip/gzip.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Gzip::Stream ();

our $VERSION = 2.0;

sub gzipmem {
    my $uncompressed = shift // return;
    my $compressed;

    Cpanel::Gzip::Stream::gzip( ref $uncompressed ? $uncompressed : \$uncompressed, \$compressed );

    if ( defined $compressed ) {
        return $compressed;
    }
    warn "Unable to compress data!";
    return $uncompressed;
}

1;
