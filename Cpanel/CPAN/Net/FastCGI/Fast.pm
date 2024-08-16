package Cpanel::CPAN::Net::FastCGI::Fast;

use strict;

#
# Copyright 2008-2010 by Christian Hansen.
# Copyright 2022 cPanel, L.L.C.
#
# This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
#

# Net::FastCGI::Protcol::PP's only downfall is the speed
# of this function.  This is an optimized version

sub build_params {
    my ($params) = @_;
    my $res = '';
    while ( my ( $key, $value ) = each(%$params) ) {
        BEGIN { ${^WARNING_BITS} = ''; }    # cheap no warnings
        if ( length $key < 0x80 && length $value < 0x80 ) {
            $res .= pack( 'CC', length $key, length $value ) . $key . $value;
        }
        elsif ( length $key < 0x80 && length $value >= 0x80 ) {
            $res .= pack( 'CN', length $key, length($value) | 0x8000_0000 ) . $key . $value;
        }
        elsif ( length $key >= 0x80 && length $value < 0x80 ) {
            $res .= pack( 'NC', length($key) | 0x8000_0000, length $value ) . $key . $value;
        }
        else {
            $res .= pack( 'NN', length($key) | 0x8000_0000, length($value) | 0x8000_0000 ) . $key . $value;
        }
    }
    return $res;
}

1;
