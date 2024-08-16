package Cpanel::Base64;

# cpanel - Cpanel/Base64.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Base64

=head1 SYNOPSIS

    my $b64 = Cpanel::Base64::encode_to_line($binstr);

=head1 DESCRIPTION

This module contains various Base64-related utilities.

=cut

#----------------------------------------------------------------------

my $LINE_WIDTH_FROM_MIME_BASE64 = 76;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $b64 = pad( $BASE64 )

Digest::SHA, JSON Web Tokens, and maybe other things give us
Base64 that lacks the trailing “padding” characters.
MIME::Base64::decode_base64(), however,
requires Base64 strings to be padded.

This function copies the string and adds on that missing
“padding”, then returns the new string.

=cut

sub pad {
    my ($b64) = @_;

    my $extra_bytes = ( length($b64) % 4 );
    if ($extra_bytes) {
        $b64 .= ( '=' x ( 4 - $extra_bytes ) );
    }

    return $b64;
}

=head2 $b64 = encode_to_line( $OCTET_STRING )

Like ordinary Base64 encoding but without any whitespace in the
encoded string.

=cut

sub encode_to_line ($in) {
    local ( $@, $! );
    require MIME::Base64;

    my $text_b64 = MIME::Base64::encode($in);
    $text_b64 =~ tr<\n><>d;

    return $text_b64;
}

=head2 $b64url = to_url( $BASE64 )

Takes an existing base64 string and converts it to base64url.

=cut

#cf. RFC 3548, section 4.
sub to_url {
    my ($b64) = @_;

    $b64 =~ tr</+><_->;
    return $b64;
}

=head2 $b64 = from_url( $BASE64URL )

The converse of C<to_url()>.

=cut

sub from_url {
    my ($b64) = @_;

    $b64 =~ tr<_-></+>;
    return $b64;
}

sub normalize_line_length {
    my ($b64) = @_;

    $b64 =~ tr< \r\n\t><>d;
    $b64 =~ s<(.{$LINE_WIDTH_FROM_MIME_BASE64})><$1\n>g;

    $b64 .= "\n" if $b64 !~ m<\n\z>;

    return $b64;
}

1;
