package B::C::Decimal;

use B::C::Std;

use B::C::Flags ();

use Exporter ();
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw/get_integer_value get_double_value u32fmt intmax/;

my $POW    = ( $B::C::Flags::Config{ivsize} * 4 - 1 );    # poor editor
my $INTMAX = ( 1 << $POW ) - 1;

# LL for 32bit -2147483648L or 64bit -9223372036854775808L
my $UL        = _ull();
my $IVDFORMAT = _ivdformat();

# values are cached in B::C::Flags::Config from POSIX
my ( $LONG_MIN, $LONG_MAX ) = ( $B::C::Flags::Config{LONG_MIN}, $B::C::Flags::Config{LONG_MAX} );
my ( $DBL_MIN,  $DBL_MAX )  = ( $B::C::Flags::Config{DBL_MIN},  $B::C::Flags::Config{DBL_MAX} );

sub intmax {
    return $INTMAX;
}

# previously known as 'sub ivx'
sub get_integer_value ($ivx) {

    # UL if > INT32_MAX = 2147483647
    my $sval = sprintf( "%${IVDFORMAT}%s", $ivx, $ivx > $INTMAX ? $UL : "" );
    if ( $ivx < -$INTMAX ) {
        $sval = sprintf( "%${IVDFORMAT}%s", $ivx, 'LL' );    # DateTime
    }

    if ( defined $LONG_MIN && $ivx == $LONG_MIN ) {
        $sval = "PERL_LONG_MIN";
    }
    elsif ( defined $LONG_MAX && $ivx == $LONG_MAX ) {
        $sval = "PERL_LONG_MAX";
    }

    $sval = '0' if $sval =~ /(NAN|inf)$/i;
    return $sval;
}

my $u32fmt = $B::C::Flags::Config{ivsize} == 4 ? "%lu" : "%u";

sub u32fmt {
    return $u32fmt;
}

# protect from warning: floating constant exceeds range of ‘double’ [-Woverflow]
# previously known as 'sub nvx'

my $NVGFORMAT = _nvgformat();

my $LL = $B::C::Flags::Config{d_longdbl} ? "LL" : "L";

sub get_double_value ($nvx) {

    # Handle infinite and NaN values
    if ( defined $nvx ) {
        if ( $B::C::Flags::Config{d_isinf} ) {
            return 'INFINITY'  if $nvx =~ /^Inf/i;
            return '-INFINITY' if $nvx =~ /^-Inf/i;
        }
        return 'NAN' if $nvx =~ /^NaN/i and $B::C::Flags::Config{d_isnan};

        # TODO NANL for long double
    }

    my $sval = sprintf( "%${NVGFORMAT}%s", $nvx, $nvx > $DBL_MAX ? $LL : "" );
    if ( $nvx < -$DBL_MAX ) {
        $sval = sprintf( "%${NVGFORMAT}%s", $nvx, $LL );
    }
    if ( defined $DBL_MIN && $nvx == $DBL_MIN ) {
        $sval = "DBL_MIN";
    }
    elsif ( defined $DBL_MAX && $nvx == $DBL_MAX ) {    #1.797693134862316e+308
        $sval = "DBL_MAX";
    }

    $sval = '0'    if $sval =~ /(NAN|inf)$/i;
    $sval .= '.00' if $sval =~ /^-?\d+$/;
    return $sval;
}

sub _ivdformat {
    my $format = $B::C::Flags::Config{ivdformat};

    # QUESTION : is it still really required ?
    $format =~ s/"//g;    #" poor editor
    return $format;
}

sub _nvgformat() {
    my $format = $B::C::Flags::Config{nvgformat};

    # QUESTION : is it still really required ?
    $format =~ s/"//g;         #" poor editor
    if ( $format eq 'g' ) {    # a very poor choice to keep precision
                               # on intel 17-18, on ppc 31, on sparc64/s390 34
                               # add one extra decimal for floating point precision ( uselongdouble should be larger than 17 but cannot check )
        $format = $B::C::Flags::Config{uselongdouble} ? '.18Lg' : '.17g';
    }
    return $format;

}

sub _ull() {
    return $B::C::Flags::Config{ivsize} == 2 * $B::C::Flags::Config{ptrsize} ? 'ULL' : 'UL';
}

1;
