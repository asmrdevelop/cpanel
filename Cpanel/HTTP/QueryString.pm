package Cpanel::HTTP::QueryString;

# cpanel - Cpanel/HTTP/QueryString.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Encoder::URI ();

#Accepts either a hashref or a key-value pair list.
#Returns a plain string. Inputs are the same as make_query_string_r
sub make_query_string {
    return ${ make_query_string_sr(@_) };
}

#Same as make_query_string, but returns a string ref.
#Use this if you might have large amounts of data.
sub make_query_string_sr {
    my $data_hr = ( 'HASH' eq ref $_[0] ) ? $_[0] : {@_};
    my ( $key, $val, @parts );

    for $key ( sort keys %$data_hr ) {
        $val = $data_hr->{$key};
        next if !defined $val;

        $key = Cpanel::Encoder::URI::uri_encode_str($key) if $key =~ tr{A-Za-z0-9\-_\.~}{}c;
        if ( 'ARRAY' eq ref $val ) {
            push @parts, map { "$key=" . ( $_ =~ tr{A-Za-z0-9\-_\.~}{}c ? Cpanel::Encoder::URI::uri_encode_str($_) : $_ ) } @$val;
        }
        else {
            push @parts, "$key=" . ( $val =~ tr{A-Za-z0-9\-_\.~}{}c ? Cpanel::Encoder::URI::uri_encode_str($val) : $val );
        }
    }

    return \join( '&', @parts );
}

#This "standard" parser will parse this:
#
# foo=bar&foo=baz&qux=1
#
# .. into this:
#
# { foo => [ qw( bar baz ) ], qux => 1 }
#
#NOTE: This expects a string reference ONLY.
#
sub parse_query_string_sr {
    my ($query_string_sr) = @_;

    my ( $key, $val, %parsed );
    for ( split m{&}, $$query_string_sr ) {
        ( $key, $val ) = map { tr/%+// ? Cpanel::Encoder::URI::uri_decode_str($_) : $_ } ( split /=/, $_, 2 )[ 0, 1 ];

        next unless defined $key;

        if ( exists $parsed{$key} ) {
            if ( ref $parsed{$key} ) {
                push @{ $parsed{$key} }, $val;
            }
            else {
                $parsed{$key} = [ $parsed{$key}, $val ];
            }
        }
        else {
            $parsed{$key} = $val;
        }
    }

    return \%parsed;
}

1;
