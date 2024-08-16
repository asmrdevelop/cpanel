package Cpanel::Encoder::XML;

# cpanel - Cpanel/Encoder/XML.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = '1.0';

# this is not uri encoding.. please dont mistake it as such.
sub xmlencode {
    my ( $self, $string ) = @_;
    $string = $self if @_ == 1;    # IE not a method call so $self is realy string

    my @characters = split /(\%[0-9a-fA-F]{2})/, $string;

    foreach (@characters) {
        if (/\%[0-9a-fA-F]{2}/) {

            # Escaped character set ...
            # IF it is in the range of 0x00-0x20 or 0x7f-0xff
            #    or it is one of  "<", ">", """, "#", "%",
            #    ";", "/", "?", ":", "@", "=" or "&"
            # THEN preserve its encoding
            unless ( /(20|7f|[0189a-fA-F][0-9a-fA-F])/i || /2[235fF]|3[a-fA-F]|40/i ) {
                s/\%([2-7][0-9a-fA-F])/sprintf "%c",hex($1)/e;
            }
        }
        else {    # Other stuff:  0x00-0x20, 0x7f-0xff, <, >, and " ... "
            s/([\000-\040\177-\377\074\076\042])/sprintf "%%%02x",unpack("C",$1)/egx;
        }
    }
    return join( '', @characters );
}

1;
