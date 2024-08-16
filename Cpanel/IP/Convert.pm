package Cpanel::IP::Convert;

# cpanel - Cpanel/IP/Convert.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings);

use Cpanel::IP::Collapse ();
use Cpanel::IP::Expand   ();
use Cpanel::Validate::IP ();

# Returns a 16-octet-long binary representation of an IP address
#
# e.g. "1.2.3.4" => "\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\4"
#
# These strings can be made human readable with
# Cpanel::IP::Convert::binip_to_human_readable_ip()
#
# AKA inet6_aton
#
sub ip2bin16 {
    my ($ip) = @_;

    $ip = '::' if !length $ip;
    $ip = Cpanel::IP::Expand::expand_ip( $ip, 6 );
    $ip =~ tr{:}{}d;

    return pack( 'H32', $ip );
}

# Returns a human readable representation of an IP address
# AKA inet6_ntoa
sub binip_to_human_readable_ip {
    my ($binip) = @_;

    return '' unless defined $binip;
    if ( length $binip == 16 ) {
        return Cpanel::IP::Collapse::collapse( join( ':', unpack( 'H4H4H4H4H4H4H4H4', $binip ) ) );
    }
    else {
        return Cpanel::IP::Collapse::collapse( join( '.', unpack( 'C4C4C4C4', $binip ) ) );
    }
}

# This normalizes a human readable IP into a common form
# Accepts a human readable IP address
#    e.g. 2001:db8:85a3::8a2e:370:7334
# Returns a normalized human readable IP address
#    e.g. 2001:0db8:85a3:0000:0000:8a2e:0370:7334
sub normalize_human_readable_ip {
    my ($ip) = @_;

    return Cpanel::IP::Convert::binip_to_human_readable_ip( Cpanel::IP::Convert::ip2bin16($ip) );
}

#This accepts one of:
#   - a single IP address
#   - a single CIDR (e.g., 1.2.3.4/8)
#   - a single IP range (e.g., 1.2.3.4-1.2.3.8)
#
#...and outputs binary ("\x0a\x9d...").
#
sub ip_range_to_start_end_address {
    my ($ip) = @_;

    my ( $start_address, $end_address );

    if ( !defined $ip ) {
        return;
    }
    elsif ( index( $ip, '/' ) > -1 && Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip) ) {
        my ( $range_firstip_binary_string, $range_lastip_binary_string ) = Cpanel::IP::Expand::first_last_ip_in_range($ip);
        $start_address = pack( 'B128', $range_firstip_binary_string );
        $end_address   = pack( 'B128', $range_lastip_binary_string );
    }
    elsif ( index( $ip, '-' ) > -1 ) {
        my ( $human_start_address, $human_end_address ) = split( m{\s*-\s*}, $ip, 2 );
        if ( Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($human_start_address) && Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($human_end_address) ) {
            $start_address = ip2bin16($human_start_address);
            $end_address   = ip2bin16($human_end_address);
        }
    }
    elsif ( Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip) ) {
        $start_address = $end_address = ip2bin16($ip);
    }
    else {
        return;
    }

    return if !length $start_address || !length $end_address;

    if ( $start_address ne $end_address && unpack( 'B128', $start_address ) ge unpack( 'B128', $end_address ) ) {
        return ( $end_address, $start_address );    # fix order
    }

    return ( $start_address, $end_address );
}

#This accepts two human-readable addresses and outputs the range as CIDR.
sub start_end_address_to_cidr {
    my ( $low, $high ) = @_;

    my $mask_length;

    my ( $low_bin, $high_bin ) = map { Cpanel::IP::Expand::ip2binary_string($_) } ( $low, $high );

    #In case something were to put IPv4 with IPv6...
    if ( length($low_bin) != length($high_bin) ) {
        die "Unmatched low/high IP address lengths: [$low] [$high]";
    }

    $low_bin =~ m<(0+)\z> or die "low should have at least one trailing 0!";
    my $low_zeros_count = length $1;

    $high_bin =~ m<(1+)\z> or die "high ($high, $high_bin) should have at least one trailing 1!";
    my $high_ones_count = length $1;

    if ( $low_zeros_count < $high_ones_count ) {
        $mask_length = $low_zeros_count;
    }
    else {
        $mask_length = $high_ones_count;
    }

    #Invert it: CIDR counts from the left.
    $mask_length = length($low_bin) - $mask_length;

    return "$low/$mask_length";
}

sub wildcard_address_to_range {
    my ($partial_ip) = @_;

    #Allow a single trailing dot, but fail on multiple trailing dots.
    chop($partial_ip) if rindex( $partial_ip, '.' ) == length($partial_ip) - 1;
    my @partial_quad = split( m{\.}, $partial_ip, -1 );

    foreach my $quad (@partial_quad) {
        if ( !length($quad) || $quad =~ tr{0-9}{}c || $quad < 0 || $quad > 255 ) {
            return;
        }
    }

    if ( !scalar @partial_quad || scalar @partial_quad > 4 ) { return; }

    while ( scalar @partial_quad < 4 ) { push @partial_quad, undef; }

    return ( join( '.', map { defined $_ ? $_ : 0 } @partial_quad ), join( '.', map { defined $_ ? $_ : 255 } @partial_quad ) );
}

sub implied_range_to_full_range {
    my ( $partial_ip, $template ) = @_;

    #5.5      - 192.168.0.0 = 192.168.0.0-192.168.5.5
    #
    my @partial_quad = split( m{\.}, $partial_ip );

    return $partial_ip if !length $partial_ip || !length $template;

    my @template_quad = split( m{\.}, $template );

    if ( scalar @partial_quad == scalar @template_quad || scalar @partial_quad == 4 || !scalar @template_quad ) {
        return $partial_ip;
    }

    splice( @template_quad, -1 * scalar @partial_quad );

    return join( '.', @template_quad, @partial_quad );
}

1;
