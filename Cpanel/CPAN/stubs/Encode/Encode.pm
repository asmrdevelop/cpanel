#
# $Id: Encode.pm,v 2.20 2007/04/22 14:56:12 dankogai Exp dankogai $
#

# This is the perl 5.6.x stub
#
package Encode;

sub DEBUG () { 0 }

require Exporter;
use base qw/Exporter/;
our @ISA    = qw( Exporter );
our @EXPORT = qw(
  decode  decode_utf8  encode  encode_utf8 str2bytes bytes2str
);
our $VERSION = '1.0';

sub encode_stub { return $_[0]; }
*encode      = *encode_stub;
*encode_utf8 = *encode_stub;
*decode_utf8 = *encode_stub;
*bytes2str   = *encode_stub;
*str2bytes   = *encode_stub;
*_utf8_off   = *encode_stub;
*_utf8_on    = *encode_stub;
*FB_PERLQQ   = *encode_stub;

sub decode {
    my $self = shift;
    if ( ref $self ) {
        my $txt = shift;
        if ( !exists $INC{'Text/Iconv.pm'} ) {
            eval ' require Text::Iconv; ';
        }
        if ( exists $INC{'Text/Iconv.pm'} ) {
            eval '	$ICONVS{$self->{"encoding"}} ||= Text::Iconv->new($self->{"encoding"}, "utf-8"); ';
            if ( exists $ICONVS{ $self->{"encoding"} } ) {
                my $decoded_txt;
                eval { $decoded_txt = $ICONVS{ $self->{'encoding'} }->convert($txt); };
                return defined $decoded_txt ? $decoded_txt : $txt;
            }
            else {
                return $txt;
            }
        }
        else {
            return $txt;
        }
    }
    else {
        return $self;
    }
}

sub name {
    my $self = shift;
    ( $self->{'encoding'} =~ /utf-?8/ ) ? 'utf8' : $self->{'encoding'};
}

sub find_encoding {
    my $enc = shift;
    my $self = { 'encoding' => $enc };
    bless $self;
    return $self;
}
