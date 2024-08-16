package Cpanel::CPAN::Net::FastCGI::IO;

#
# Copyright 2008-2010 by Christian Hansen.
# Copyright 2022 cPanel, L.L.C.
#
# This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
#

use strict;
use warnings;
use warnings::register;

use Errno qw[EBADF EINTR EPIPE];
use Net::FastCGI::Constant qw[FCGI_HEADER_LEN];
use Net::FastCGI::Protocol qw[parse_record];

# Modified to throw an exception on error
sub read_record {
    my ($fh) = @_;

    my $len = FCGI_HEADER_LEN;
    my $off = 0;
    my $buf;

    while ($len) {
        my $r = sysread( $fh, $buf, $len, $off );
        if ( defined $r ) {
            last unless $r;
            $len -= $r;
            $off += $r;
            if ( !$len && $off == FCGI_HEADER_LEN ) {
                $len = vec( $buf, 2, 16 )    # Content Length
                  + vec( $buf, 6, 8 );       # Padding Length
            }
        }
        elsif ( $! != EINTR ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'IO::ReadError', [ error => $!, length => $len ] );
        }
    }
    if ($len) {
        $! = $off ? EPIPE : 0;
        if ($off) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'IO::ReadError', [ error => $!, length => $len ] );
        }
        return;
    }
    return parse_record($buf);
}
1;

