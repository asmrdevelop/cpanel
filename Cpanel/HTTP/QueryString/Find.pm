package Cpanel::HTTP::QueryString::Find;

# cpanel - Cpanel/HTTP/QueryString/Find.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Encoder::URI ();

#----------------------------------------------------------------------
#The functions below are useful for "peeking" into a query string without
#actually parsing it.
#----------------------------------------------------------------------

sub value_in_query_string {
    my ( $key, $haystack_sr ) = @_;

    return ${ _value_in_query_string_sr( $key, $haystack_sr ) };
}

sub _value_in_query_string_sr {
    my ( $key, $haystack_sr ) = @_;

    my $simple_search_key = Cpanel::Encoder::URI::uri_encode_str($key);

    my $value;

    #Much faster, simpler way of getting the value.
    #This won't catch it, though, if the value straddles two chunks
    #or if for some reason they've hex-encoded the key.
    my $offset = index( $$haystack_sr, "$simple_search_key=" );

    if ( $offset != -1 && ( $offset == 0 || substr( $$haystack_sr, $offset - 1, 1 ) eq '&' ) ) {

        my $pos = pos $$haystack_sr;

        pos $$haystack_sr = $offset + length($simple_search_key) + 1;
        ($value) = ( $$haystack_sr =~ m{\G([^&]*)} );

        pos $$haystack_sr = $pos;
    }

    #If that didn't work, then try a regexp that will match
    #each part of the query string encoded or not encoded
    if ( !defined $value ) {
        my $regexp = get_regexp_to_match_any_query_string($key);
        ($value) = ( $$haystack_sr =~ m{(?:\A|&)$regexp=([^&]*)} );
    }

    $value = $value && Cpanel::Encoder::URI::uri_decode_str($value);

    return \$value;
}

#Might as well cache these.
my %string_regexp_cache;
my $uri_encoded_space;

# This function creates a regexp that will match a encode
# unencoded or semi encoded query string.
sub get_regexp_to_match_any_query_string {
    my ($str) = @_;

    if ( !$string_regexp_cache{$str} ) {
        my @ords = ( unpack( 'H*', $str ) =~ m{..}g );

        my $regexp = join( q{}, map { '(?:' . Cpanel::Encoder::URI::uri_encode_str($_) . "|%$ords[0]|%" . uc( shift @ords ) . ')' } split m{}, $str );

        $uri_encoded_space ||= Cpanel::Encoder::URI::uri_encode_str(' ');
        $regexp =~ s{(\Q$uri_encoded_space\E\|)}{$1\[+\]|}g;

        $string_regexp_cache{$str} = qr{$regexp};
    }

    return $string_regexp_cache{$str};
}

1;
