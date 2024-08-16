package Cpanel::JSON::Sanitize;

# cpanel - Cpanel/JSON/Sanitize.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::JSON::Sanitize - Functions for sanitizing and converting JSON.

=head1 SYNOPSIS

    use Cpanel::JSON::Sanitize ();

    my $json_text = Cpanel::JSON::Sanitize::sanitize_for_dumping($ref);

    Cpanel::JSON::Sanitize::uxxxx_to_bytes($content);

=head1 DESCRIPTION

This module is used to dump JSON and format JSON for dumping. It does
not do any security sanitization.

=cut

=head2 sanitize_for_dumping($ref)

Dumps a reference as JSON text.

This does not provide any sanitization security-wise, but it does make a deep
copy of the structure and then removes anything that is not a hashref,
arrayref, scalarref to 1 or 0, scalar, or undef.

=cut

sub sanitize_for_dumping {
    my $item    = shift;
    my $reftype = ref $item;

    if ( !defined $item || $reftype eq "" ) {
        return $item;
    }
    elsif ( ( $reftype eq 'SCALAR' || $reftype eq 'JSON::XS::Boolean' || $reftype eq 'JSON::PP::Boolean' || $reftype eq 'Types::Serialiser::Boolean' ) && ( $$item eq '1' || $$item eq '0' ) ) {
        return $item;
    }
    elsif ( $reftype eq "ARRAY" ) {
        return [ map { sanitize_for_dumping($_) } grep { _suitable_for_dumping($_) } @$item ];
    }
    elsif ( $reftype eq "HASH" ) {
        return {
            map    { $_ => sanitize_for_dumping( $item->{$_} ) }
              grep { _suitable_for_dumping( $item->{$_} ) }
              keys %$item
        };
    }
    else {
        # This will only be triggered if the initial call contains a bad item.
        die "That data structure isn't suitable for dumping.";
    }
}

=head2 $scalar = filter_to_json( $SCALAR )

Recursively iterates through $SCALAR, calling C<TO_JSON()> on all
blessed references (i.e., objects) that support such a method.
Throws an exception if it finds an object that doesn’t support it.

This is useful for replacing JSON with Sereal, CBOR, or some other
comparable serialization.

=cut

sub filter_to_json ($item) {
    my $ref = ref $item;

    return $item if !$ref;

    if ( 'ARRAY' eq $ref ) {
        return [ map { filter_to_json($_) } @$item ];
    }
    elsif ( 'HASH' eq $ref ) {
        my %dupe = map { ( $_ => filter_to_json( $item->{$_} ) ) } keys %$item;

        return \%dupe;
    }
    elsif ( UNIVERSAL::can( $item, 'TO_JSON' ) ) {
        return filter_to_json( $item->TO_JSON() );
    }

    require Carp;
    Carp::croak("$item is not JSON-compatible!");
}

=head2 uxxxx_to_bytes($scalar_ref)

Converts \uXXXX sequences to bytes in a scalar reference.

JSON::XS will serialize \uXXXX sequences to UTF-8 rather than bytes.
That’s a problem because we like to work in bytes. It doesn’t work just to
encode() the result, either, because there may be bytes alongside the
\uXXXX sequence. Our solution, then, is to convert the \uXXXX
sequences into bytes before we parse the JSON.

NOTE: Should cPanel’s custom no_set_utf8() affect the decode of \uXXXX??
That would obviate this logic.

=cut

sub uxxxx_to_bytes {
    my $str_r = \$_[0];

    $$str_r =~ s/
        (\\+)u( [a-fA-F0-9]{4} )
    /
        if ( length($1) % 2 ) {
            my $c = pack('U', hex $2);
            utf8::encode($c);
            substr($1, 1) . $c;
        }
        else {
            "$1u$2";
        }
    /exg;

    return $$str_r;
}

sub _suitable_for_dumping {
    my $item    = shift;
    my $reftype = ref $item;

    return 1 if !defined $item;
    return 1 if $reftype eq "" || $reftype eq 'ARRAY' || $reftype eq 'HASH';
    return 1 if ( $reftype eq 'SCALAR' || $reftype eq 'JSON::XS::Boolean' || $reftype eq 'JSON::PP::Boolean' || $reftype eq 'Types::Serialiser::Boolean' ) && ( $$item eq '1' || $$item eq '0' );
    return 0;
}

1;
