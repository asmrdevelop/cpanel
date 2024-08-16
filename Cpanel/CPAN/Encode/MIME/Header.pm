package Cpanel::CPAN::Encode::MIME::Header;

use strict;
use warnings;

use Encode ();
use Carp   ();

sub decode($;$) {
    my ( $str, $chk ) = @_;

    # zap spaces between encoded words
    $str =~ s/\?=\s+=\?/\?==\?/gos;

    # multi-line header to single line
    $str =~ s/(?:\r\n|[\r\n])[ \t]//gos;
    1 while ( $str =~ s/(=\?[-0-9A-Za-z_]+\?[Qq]\?)(.*?)\?=\1(.*?\?=)/$1$2$3/ );    # Concat consecutive QP encoded mime headers
                                                                                    # Fixes breaking inside multi-byte characters
    $str =~ s{
        =\?              # begin encoded word
        ([-0-9A-Za-z_]+) # charset (encoding)
        (?:\*[A-Za-z]{1,8}(?:-[A-Za-z]{1,8})*)? # language (RFC 2231)
        \?([QqBb])\?     # delimiter
        (.*?)            # Base64-encodede contents
        \?=              # end encoded word
    }{
	if ($2 =~ tr/bB//) {
            decode_b($1, $3, $chk);
        } elsif ($2 =~ tr/qQ//) {
            decode_q($1, $3, $chk);
        } else {
            Carp::croak qq(MIME "$2" encoding is nonexistent!);
        }
    }egox;
    $_[1] = $str if $chk;
    return $str;
}

sub decode_b {
    my $enc  = shift;
    my $d    = Encode::find_encoding($enc) or Carp::croak qq(Unknown encoding "$enc");
    my $db64 = decode_base64(shift);
    return '' unless defined $db64;
    my $chk = shift;
    return $d->name eq 'utf8'
      ? Encode::decode_utf8($db64)
      : $d->decode( $db64, $chk || Encode::FB_PERLQQ );
}

sub decode_q {
    my ( $enc, $q, $chk ) = @_;
    my $d = Encode::find_encoding($enc) or Carp::croak qq(Unknown encoding "$enc");
    $q =~ s/_/ /go;
    $q =~ s/=([0-9A-Fa-f]{2})/pack("C", hex($1))/ego;
    return $d->name eq 'utf8'
      ? Encode::decode_utf8($q)
      : $d->decode( $q, $chk || Encode::FB_PERLQQ );
}

sub decode_base64 {
    my $str = shift;
    my $res = "";

    $str =~ tr|A-Za-z0-9+=/||cd;
    if ( length($str) % 4 ) { return; }
    $str =~ s/=+$//;
    $str =~ tr|A-Za-z0-9+/| -_|;
    while ( $str =~ /(.{1,60})/gs ) {
        my $len = chr( 32 + length($1) * 3 / 4 );
        $res .= unpack( "u", $len . $1 );
    }
    return $res;
}

1;
