package Cpanel::BitConvert;

# cpanel - Cpanel/BitConvert.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module is in the public domain.
use strict;

use Cpanel::IP::Convert ();

# In this module, "string" refers to a binary string containing the IPv4 or IPv6
# address, "bits" refers to a string containing 32 or 128 ASCII "0" or "1"
# characters, and "ip" refers to a standard human-readable IP address.

sub convert_string_ipbits {
    my $n = shift;
    return ( split //, unpack 'B*', $n );
}

sub convert_bits_string {
    my $bits = shift;
    my $n    = join '', @$bits;

    return pack 'B*', '0' x ( 128 - length $n ) . $n if length($n) > 32;
    return pack 'B*', '0' x ( 32 - length $n ) . $n;
}

sub convert_string_ip {
    my $n = shift;
    return Cpanel::IP::Convert::binip_to_human_readable_ip($n) if length($n) == 16;
    return join '.', unpack 'C*', $n;
}

sub convert_ip_string {
    my $ip = shift;
    return Cpanel::IP::Convert::ip2bin16($ip) if $ip =~ /:/;
    return pack "C*", split /\./, $ip;
}

sub do_chunk {
    my ( $chunks, $fbits, $lbits ) = @_;
    my ( @prefix, $idx1, $idx2, $size );
    $idx1 = 0;
    $idx1++ while ( $idx1 <= $#$fbits and $$fbits[$idx1] eq $$lbits[$idx1] );
    @prefix = @$fbits[ 0 .. $idx1 - 1 ];

    $idx2 = $#$fbits;
    $idx2-- while ( $idx2 >= $idx1 and $$fbits[$idx2] eq '0' and $$lbits[$idx2] eq '1' );

    if ( $idx2 >= $idx1 ) {
        $size = $#$fbits - $idx1;
        do_chunk( $chunks, $fbits, [ @prefix, ( split //, '0' . '1' x $size ) ] );
        do_chunk( $chunks, [ @prefix, ( split //, '1' . '0' x $size ) ], $lbits );
    }
    else {
        $size = $#$fbits - $idx2;
        push @$chunks, [ ( convert_bits_string [ @prefix, ( split //, '0' x $size ) ] ), @$fbits - $size ];
    }
    return;
}

sub convert_iprange_cidrs {
    my $ip0 = shift;
    my $ip1 = shift;

    my ( @chunks, @fbits, @lbits );

    my $ip0_number = convert_ip_string $ip0;
    my $ip1_number = convert_ip_string $ip1;

    return if ( $ip0_number gt $ip1_number );

    @fbits = convert_string_ipbits $ip0_number;
    @lbits = convert_string_ipbits $ip1_number;

    do_chunk( \@chunks, \@fbits, \@lbits );
    my @ipl;

    for (@chunks) {
        my ( $n, $m ) = @$_;
        push( @ipl, convert_string_ip($n) . "/$m" );
    }
    return @ipl;
}

sub mask2cidr {
    my ($mask) = @_;
    my ( @d, $n, $bits );

    if ( $mask eq '0.0.0.0' ) {
        return '0';
    }
    @d    = split /\./, $mask;
    $n    = ( ( ( ( ( $d[0] * 256 ) + $d[1] ) * 256 ) + $d[2] ) * 256 ) + $d[3];
    $bits = 32;
    while ( ( $n % 2 ) == 0 ) {
        $n >>= 1;
        $bits -= 1;
    }
    return $bits;
}

1;
