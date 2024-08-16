package Cpanel::Encoder::Tiny::Rare;

# cpanel - Cpanel/Encoder/Tiny/Rare.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Encoder::Tiny::Rare - Rarely used Encoder functions

=head1 SYNOPSIS

    use Cpanel::Encoder::Tiny::Rare ();

    my $decoded_string = Cpanel::Encoder::Tiny::Rare::angle_bracket_decode("&gt;");

=head1 DESCRIPTION

Tools for decoding, encoding, and removing html.

=cut

=head2 angle_bracket_decode($string)

Convert HTML encoded angle brackets back to angle
brackets

=cut

sub angle_bracket_decode {
    my ($string) = @_;
    $string =~ s{ &lt; }{<}xmsg;
    $string =~ s{ &gt; }{>}xmsg;
    return $string;
}

=head2 decode_utf8_html_entities($string)

Convert HTML encoded UTF-8 characters back to
the actual characters

=cut

sub decode_utf8_html_entities {
    my $str = shift;
    $str =~ s/&\#(\d{4})\;/chr($1);/eg;
    return $str;
}

#Special CSS encoding: IE <9 doesn't understand back-escaped
#single-quote and double-quote, but it does understand
#URL-encoding, so URI-encode these: ()\s"'
#Were it not for IE <9, we could just back-escape quotes.
my %uri_encoding_cache = (
    '"'  => '%22',
    q{'} => '%27',
    '('  => '%28',
    ')'  => '%29',
    q{ } => '%20',
    "\t" => '%09',
);

=head2 css_encode_str($string)

IE-9 compatible css character encoder.

=cut

sub css_encode_str {
    my $str = shift;
    $str =~ s{([\(\)\s"'])}{
        $uri_encoding_cache{$1}
        #...on the extremely minimal (?) chance that this gets [^\S \t]
        || require Cpanel::Encoder::URI && Cpanel::Encoder::URI::uri_encode_str($1)
    }ge;
    return $str;
}

1;
