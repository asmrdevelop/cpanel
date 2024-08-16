package Cpanel::Validate::IP::Expand;

# cpanel - Cpanel/Validate/IP/Expand.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::IP     ();
use Cpanel::Validate::IP::v4 ();

sub normalize_ipv4 {
    return unless Cpanel::Validate::IP::v4::is_valid_ipv4( $_[0] );
    return join '.', map { $_ + 0 } split /\./, $_[0];
}

sub expand_ipv6 {
    my $ip = shift;

    return unless Cpanel::Validate::IP::is_valid_ipv6($ip);

    return $ip if length $ip == 39;    # already expanded

    my @seg = split /:/, $ip, -1;

    # Clean up leading/trailing double colon effects.
    $seg[0]  = '0000' if !length $seg[0];
    $seg[-1] = '0000' if !length $seg[-1];

    if ( $seg[-1] =~ tr{.}{} && Cpanel::Validate::IP::v4::is_valid_ipv4( $seg[-1] ) ) {
        my @ipv4 = split /\./, normalize_ipv4( pop @seg );
        push @seg, sprintf( '%04x', ( $ipv4[0] << 8 ) + $ipv4[1] ), sprintf( '%04x', ( $ipv4[2] << 8 ) + $ipv4[3] );
    }
    my @exp;
    for my $seg (@seg) {
        if ( !length $seg ) {
            my $count = scalar(@seg) - scalar(@exp);
            while ( $count + scalar(@exp) <= 8 ) {
                push @exp, '0000';
            }
        }
        else {
            push @exp, sprintf( '%04x', hex $seg );
        }
    }
    return join ':', @exp;
}

sub normalize_ipv6 {
    my $ip = shift;

    return unless $ip = expand_ipv6($ip);

    $ip = lc($ip);

    # do some basic flattening #
    $ip =~ s/:(0+:){2,}/::/;         # flatten multiple groups of 0's to :: #
    $ip =~ s/(:0+){2,}$/::/;         # flatten multiple groups of 0's to :: #
    $ip =~ s/^0+([1-9a-f])/$1/;      # flatten the first segment's leading 0's to a single 0 #
    $ip =~ s/:0+([1-9a-f])/:$1/g;    # flatten each segment, after the first, leading 0's to a single 0 #
    $ip =~ s/:0+(:)/:0$1/g;          # flatten any segments that are just 0's to a single 0 #
    $ip =~ s/:0+$/:0/g;              # flatten the end segment if it's just 0's to a single 0 #
    $ip =~ s/^0+::/::/;              # remove single 0 at the beginning #
    $ip =~ s/::0+$/::/;              # remote single 0 at the end #

    return $ip;

}

sub normalize_ip {
    return !defined $_[0] ? undef : index( $_[0], ':' ) > -1 ? normalize_ipv6( $_[0] ) : normalize_ipv4( $_[0] );
}

# "Expansion" isn't really meaningful with respect to IPv4, so we'll
# return a normalized version.
sub expand_ip {
    return !defined $_[0] ? undef : index( $_[0], ':' ) > -1 ? expand_ipv6( $_[0] ) : normalize_ipv4( $_[0] );
}

1;
