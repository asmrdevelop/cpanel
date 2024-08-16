package Cpanel::Encoder::utf8;

# cpanel - Cpanel/Encoder/utf8.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub teletex_to_utf8 {
    my ($value) = @_;
    my @chrs = unpack( 'C*', $value );
    my @string;
    while ( my @cl = splice( @chrs, 0, 1 ) ) {
        push @string, pack( 'U', $cl[0] );
    }
    return join( '', @string );
}

sub ucs2_to_utf8 {
    my ($value) = @_;
    my @chrs = unpack( 'C*', $value );

    my @string;
    while ( my @cl = splice( @chrs, 0, 2 ) ) {
        push @string, pack( 'U', hex( sprintf( "%02x%02x", @cl ) ) );
    }
    my $ret = join( '', @string );

    return $ret;
}

sub is_utf8 {
    require bytes;
    return 1 if bytes::length( $_[0] ) != length( $_[0] );
    return 0;
}

sub encode {
    use bytes;    # only for the scope of this subroutine
    $_[0] = substr $_[0], 0;
    return;
}

1;

__END__

=head1 NAME

Cpanel::Encoder::utf8

=head1 SYNOPSIS

  use Cpanel::Encoder::utf8 ();
  $string = "\x{2b2b}";
  Cpanel::Encoder::utf8::encode($string) if Cpanel::Encoder::utf8::is_utf8($string);

=head1 DESCRIPTION

Perl 5.6.2's utf8 support is fairly limited and doesn't support
utf8::is_utf8() or utf8::encode(). This module provides crude
implementations of those two functions which may be used in
5.6.x code. The provided encode() function takes advantage
of the fact that perl's internal representation of wide characters
is actually utf8 already. Note that this trick is something that a
modern perl's perldoc perlunifaq explicitly advises against:

    But don't be lazy, and don't use the fact that Perl's internal
    format is UTF-8 to your advantage.

This module can disappear once we are able to move to a more modern
perl.
