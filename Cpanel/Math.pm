package Cpanel::Math;

# cpanel - Cpanel/Math.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '2.0';

my $nonetxt;
my $locale;

*floatto            = *_floatNum;
*_toHumanSize       = *_real_toHumanSize;
*human_format_bytes = *_real_toHumanSize;

sub ceil {
    my $cval = int $_[0];

    # ? $cval++ : does not result in "$cval incremented by one" return, it actually acts like floor()
    return ( ( $_[0] - $cval ) > 0 ) ? ( $cval + 1 ) : $cval;
}

# for those that assume if we have a ceiling we'll also have a floor
sub floor { return int $_[0]; }

sub _floatNum {
    return sprintf( "%.$_[1]f", $_[0] );
}

sub get_none_text {
    return 'None' if $Cpanel::Parser::Vars::altmode;    # WHY DO WE DO THIS? If there is a reason please update this comment to explain
    return ( $nonetxt = _locale()->maketext('None') );
}

sub _real_toHumanSize {
    if ( !$_[0] && $_[1] ) {
        return defined $nonetxt ? $nonetxt : get_none_text();
    }
    return _locale()->format_bytes( $_[0] );
}

sub roundto {

    # previouse ternary always went up to the next, so 9 resulted in 10 but 6 also resulted in 10 instead of 5
    return $_[0] >= $_[2] ? $_[2] : $_[1] * int( ( $_[0] + 0.50000000000008 * $_[1] ) / $_[1] );
}

#e.g., divide 30 into 6 pieces (5 each) but with
#a random translation. So, you could get any of these:
#
#   0   5   10  15  20  25
#   1   6   11  16  21  26
#   2   7   12  17  22  27
#   3   8   13  18  23  28
#   4   9   14  19  24  29
#

#This is useful when, e.g., you want to schedule cron jobs
#but don’t want them *all* to occur at zero hours/minutes/etc.
#
sub divide_with_random_translation {
    my ( $range, $divisor ) = @_;    #“range”, i.e., [ 0 .. $range ]

    die 'Call in list context!' if !wantarray;

    ( $_ != int ) && die "Integers only, not “$_”!" for ( $range, $divisor );

    if ( $range % $divisor ) {
        die "Invalid divisor: “$divisor” (must be a factor of $range)!";    #XXX
    }

    my $first_tick = int rand $divisor;

    my $ticks_count = $range / $divisor;

    return map { $first_tick + $_ * $divisor } ( 0 .. ( $ticks_count - 1 ) );
}

sub _locale {
    return $locale if defined $locale;
    eval 'require Cpanel::Locale';
    return ( $locale = 'Cpanel::Locale'->get_handle() );

}

1;

__END__

* (See case 4591) having 'if ($has_fastmath) { return Cpanel::FastMath::roundto( $_[0], $_[1], $_[2] ); }' in roundto() to also makes it about 2% slower

roundto() really looks like this, but the above form (terinary) is about 2-5% faster than the if/return form
(of note: if _roundto() below did not unpack @_ it'd be about 14% faster itself)
See case 4591 for benchmarking details.

sub _roundto {
    my ( $num, $incr, $top ) = @_;
    if ( $num >= $top ) { return $top; }
    return ( $num + ( -$num % $incr ) );
}


sub _floatNum {
    my ( $num, $per ) = @_;
    return sprintf( "%.${per}f", $num );
}
