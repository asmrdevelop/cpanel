package Cpanel::SSH::ASN;

use strict;

#this is a subset of ASN.1 parsing, meant for decoding RSA2/DSA private keys
#Encoding::BER from CPAN will do this more full-featuredly.

sub new {
    my $class = shift();

    my ( $tag, $value ) = @_;

    my $this = {
        'tag'   => $tag   || 0,
        'value' => $value || q{},
    };

    return bless $this, $class;
}

#takes a reference or a scalar
sub decode {
    my $this   = shift();
    my $buffer = shift();

    my $buffer_is_ref = ref $buffer eq 'SCALAR';

    my $size;

    $this->{'tag'} = _read_byte( $buffer_is_ref ? $buffer : \$buffer );

    my $first_byte = _read_byte( $buffer_is_ref ? $buffer : \$buffer );

    if ( $first_byte < 127 ) {
        $size = $first_byte;
    }
    elsif ( $first_byte > 127 ) {
        my $size_length = $first_byte - 0x80;    #128
        $size = _bin_to_int( _read_bytes( $buffer_is_ref ? $buffer : \$buffer, $size_length ) );
    }
    else {
        die();                                   #invalid ASN length value
    }

    return $this->{'value'} = _read_bytes( $buffer_is_ref ? $buffer : \$buffer, $size );
}

#takes a reference only
sub _read_byte {
    return ord( _read_bytes( shift(), 1 ) );
}

#takes a reference only
sub _read_bytes {
    my $buffer_sr = shift();
    my $length    = shift();
    my $result    = substr( $$buffer_sr, 0, $length );
    $$buffer_sr = substr( $$buffer_sr, $length );

    return $result;
}

sub _bin_to_int {
    my $bin    = shift();
    my $length = length $bin;

    my $result = 0;

    for my $i ( 0 .. $length - 1 ) {
        my $cur_byte  = _read_byte( \$bin );
        my $bit_shift = ( $length - $i - 1 ) * 8;
        $result += $cur_byte << $bit_shift;
    }

    return $result;
}

sub get_sequence {
    my $this = shift();
    my $seq  = $this->{'value'};
    my @result;

    while ( length $seq ) {
        my $cur_val = __PACKAGE__->new();
        $cur_val->decode( \$seq );
        push @result, $cur_val;
    }

    return wantarray ? @result : \@result;
}

1;
