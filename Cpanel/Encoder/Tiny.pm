package Cpanel::Encoder::Tiny;

# cpanel - Cpanel/Encoder/Tiny.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %XML_ENCODE_MAP  = ( '&'   => '&amp;', '<'  => '&lt;', '>'  => '&gt;', '"'    => '&quot;', "'"    => '&apos;' );
my %HTML_ENCODE_MAP = ( '&'   => '&amp;', '<'  => '&lt;', '>'  => '&gt;', '"'    => '&quot;', "'"    => '&#39;' );
my %HTML_DECODE_MAP = ( 'amp' => '&',     'lt' => '<',    'gt' => '>',    'quot' => '"',      'apos' => q{'}, '#39' => q{'} );

my $decode_regex = do { my $tmp = join( '|', keys %HTML_DECODE_MAP ); "&($tmp);"; };

sub angle_bracket_encode {
    my ($string) = @_;
    $string =~ s{<}{&lt;}xmsg;
    $string =~ s{>}{&gt;}xmsg;
    return $string;
}

sub safe_xml_encode_str {
    my $data = join( '', @_ );
    return $data if $data !~ tr/&<>"'//;
    $data =~ s/([&<>"'])/$XML_ENCODE_MAP{$1}/sg;
    return $data;
}

#
# This is optimized for the most common case
# where there is actually nothing to encode and
# only one argument is passed in.
#
sub safe_html_encode_str {
    return $_[0] if !defined $_[0] || ( !defined $_[1] && $_[0] !~ tr/&<>"'// );
    my $data = defined $_[1] ? join( '', @_ ) : $_[0];
    return $data if $data !~ tr/&<>"'//;
    $data =~ s/([&<>"'])/$HTML_ENCODE_MAP{$1}/sg;
    return $data;
}

sub safe_html_decode_str {
    return undef if !defined $_[0];
    my $data = join( '', @_ );
    $data =~ s/$decode_regex/$HTML_DECODE_MAP{$1}/g;
    return $data;
}

sub css_encode_str {
    require Cpanel::Encoder::Tiny::Rare;
    *css_encode_str = *Cpanel::Encoder::Tiny::Rare::css_encode_str;
    goto \&Cpanel::Encoder::Tiny::Rare::css_encode_str;
}

1;
