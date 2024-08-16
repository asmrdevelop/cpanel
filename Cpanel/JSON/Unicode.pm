package Cpanel::JSON::Unicode;

# cpanel - Cpanel/JSON/Unicode.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This has to run in system perl, so no cPstrict.pm.
# Also no signatures, since system perl on RH7 is 5.16.
#
use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::JSON::Unicode

=head1 SYNOPSIS

    # Avoid this module unless needed:
    #
    if (-1 != index($json, '\\u')) {
        Cpanel::JSON::Unicode::replace_unicode_escapes_with_utf8(\$json);
    }

    my $decoded_utf8 = JSON::XS->new->decode($json);

=head1 DESCRIPTION

This module implements logic related to JSON and Unicode.

=cut

#----------------------------------------------------------------------

use constant {

    # This is usually called the “high” surrogate, which is confusing
    # because the value itself is the _low_ surrogate. So we use “lead
    # and “tail” instead.
    #
    _LEAD_SURROGATE_MIN => 0xd800,
    _TAIL_SURROGATE_MIN => 0xdc00,

    _SURROGATE_MASK => 0xfc00,

    _BACKSLASH_ORD    => 0x5c,
    _DOUBLE_QUOTE_ORD => 0x22,
};

my $UNICODE_ESCAPE_REGEXP = qr/

    # No backslashes prior:
    (?<!\x5c)

    (

        # Ignore pairs of backslashes:
        (?:\x5c\x5c)*

        \x5c u ([0-9a-fA-F]{4})
    )
/x;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 replace_unicode_escapes_with_utf8( \$JSON_BYTES )

Takes in a JSON string and replaces nonessential Unicode escape sequences
with the equivalent UTF-8.

This is useful because CPAN’s standard JSON modules don’t implement a
“bytes-in-bytes-out” decoder interface; L<JSON::PP> and related modules
all implement C<utf8(0)>, which is “characters-in-characters-out”, and
C<utf8(1)>, which is “bytes-in-characters-out”. C<utf8(0)> can I<almost>
be used for “bytes-in-bytes-out”, but Unicode escape sequences (e.g.,
C<\u00e9>) will be decoded as Unicode characters, not raw (UTF-8) bytes.

The maintainers of those modules have declined to add this ability to the
JSON modules themselves (even when sent patches); however, cPanel needs
this in order to handle JSON Unicode escape sequences properly.

This function provides a workaround: “surgically” replace Unicode escapes
with the equivalent UTF-8. That way, C<utf8(0)> I<can> function as a
“bytes-in-bytes-out” decoder: call this function on your JSON, then decode
the JSON.

B<CAVEAT:> This is not optimized. Avoid this function I<unless> the JSON
string needs it; see the L</SYNOPSIS> for an example.

=cut

sub replace_unicode_escapes_with_utf8 {
    my ($json_sr) = @_;

    my $lead_surrogate;

    my $ret = $$json_sr =~ s<$UNICODE_ESCAPE_REGEXP><
        _replacement(\$lead_surrogate, $json_sr, $+[0], @{^CAPTURE})
    >ge;

    if ($lead_surrogate) {
        die sprintf "Incomplete surrogate pair (0x%04x)", $lead_surrogate;
    }

    return $ret;
}

sub _replacement {
    my ( $lead_surrogate_sr, $json_sr, $match_end, @captures ) = @_;

    my $num = hex $captures[1];

    if ( ( $num & _SURROGATE_MASK ) == _TAIL_SURROGATE_MIN ) {
        if ($$lead_surrogate_sr) {
            my $utf8 = _decode_surrogates( $$lead_surrogate_sr, $num );
            $$lead_surrogate_sr = undef;
            return $utf8;
        }

        die sprintf "Unpaired trailing surrogate (0x%04x)", $num;
    }
    elsif ( ( $num & _SURROGATE_MASK ) == _LEAD_SURROGATE_MIN ) {
        my $next2 = substr( $$json_sr, $match_end, 2 );
        if ( !$next2 || $next2 ne '\\u' ) {
            die sprintf "Unpaired leading surrogate (0x%04x)", $num;
        }

        $$lead_surrogate_sr = $num;
        return q<>;
    }
    elsif ( $num < 0x20 || $num == _BACKSLASH_ORD || $num == _DOUBLE_QUOTE_ORD ) {
        return $captures[0];
    }

    my $utf8 = chr $num;
    utf8::encode($utf8);
    return $utf8;
}

# from perlunicode, via JSON::PP, tweaked:
#
sub _decode_surrogates {
    my ( $lead, $tail ) = @_;

    my $uni = 0x10000 + ( ( $lead - 0xd800 ) << 10 ) + ( $tail - 0xdc00 );

    my $un = chr $uni;
    utf8::encode($un);

    return $un;
}

1;
