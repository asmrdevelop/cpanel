package Cpanel::Date::Format;

# cpanel - Cpanel/Date/Format.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Date::Format - CLDR date formatting without L<DateTime>

=head1 SYNOPSIS

    my $str = Cpanel::Date::Format::translate_for_locale(
        time(),
        'time_format_short',
        'fr',
    );

=head1 DESCRIPTION

It’s pretty rare that we need all of L<DateTime>’s firepower, but we
not infrequently need to translate dates on the server.

This module provides that ability with very little overhead.

=cut

use Cpanel::JSON ();

my $_CLDR_DIR       = '/usr/local/cpanel/base/cjt/cldr';
my $FALLBACK_LOCALE = 'en';

my %LOCALE_CLDR;

=head1 FUNCTIONS

=head2 translate_for_locale( EPOCH, FORMAT_NAME, LOCALE_SYMBOL )

Analogous to L<DateTime>’s C<format_cldr()> method, it returns the date
as a localized string. (Unlike L<DateTime>, this function returns bytes,
not UTF-8 characters.)

EPOCH is a unix timestamp (e.g., the return of C<time()>).

FORMAT_NAME must match
this pattern: C<(date|time|datetime)_format_(short|medium|long|full)>.

LOCALE_SYMBOL is a locale tag, as returned by L<Cpanel::Locale>’s
C<get_language_tag()> method.

=cut

sub translate_for_locale {
    my ( $epoch, $format_name, $locale_symbol ) = @_;

    my $cldr_hr = $LOCALE_CLDR{$locale_symbol} ||= do {
        local $@;
        eval { _load_locale($locale_symbol) } || do {
            warn "Failed to load date/time values for “$locale_symbol” ($@); falling back to $FALLBACK_LOCALE";
            _load_locale($FALLBACK_LOCALE);
        };
    };

    my $pattern = $cldr_hr->{$format_name} or do {
        die "Unknown $locale_symbol CLDR date/time format name: “$format_name”";
    };

    return _translate_using_pattern( $epoch, $cldr_hr, $pattern );
}

#accessed from tests
sub _load_locale {
    my ($locale_symbol) = @_;

    # Handle es-419 properly.
    $locale_symbol =~ tr/-/_/;

    my $lang_symbol = $locale_symbol =~ s/_.*//r;

    foreach my $sym ( $locale_symbol, $lang_symbol ) {
        return Cpanel::JSON::LoadFile("$_CLDR_DIR/$sym.json") if -r "$_CLDR_DIR/$sym.json";
    }
    return;
}

my $twelve_hrs;

sub _translate_using_pattern {
    my ( $epoch, $cldr_hr, $cldr_pattern ) = @_;

    #Avoid Cpanel::Time here because we might only need the time,
    #not the year/month, and for month it’s handier to have a 0-indexed
    #month number anyway.
    my (@smhdmyw) = gmtime $epoch;

    return $cldr_pattern =~ s{
        ('[^']+')   #quoted string
        |
        (([a-zA-Z])\3*) #replacement pattern
    }
    {
        length $1
            ? substr( $1, 1, length($1) - 2 )

            #NOTE: This logic should stay in sync with that in
            #CJT2’s datetime().
            : do {

                #year
                if ($2 eq 'yy') {
                    substr( 1900 + $smhdmyw[5], -2 );
                }
                elsif (($2 eq 'y') || ($2 eq 'yyy') || ($2 eq 'yyyy')) {
                    1900 + $smhdmyw[5];
                }

                #month
                elsif ($2 eq 'MMMMM') {
                    $cldr_hr->{'month_format_narrow'}[ $smhdmyw[4] ];
                }
                elsif ($2 eq 'LLLLL') {
                    $cldr_hr->{'month_stand_alone_narrow'}[ $smhdmyw[4] ];
                }
                elsif ($2 eq 'MMMM') {
                    $cldr_hr->{'month_format_wide'}[ $smhdmyw[4] ];
                }
                elsif ($2 eq 'LLLL') {
                    $cldr_hr->{'month_stand_alone_wide'}[ $smhdmyw[4] ];
                }
                elsif ($2 eq 'MMM') {
                    $cldr_hr->{'month_format_abbreviated'}[ $smhdmyw[4] ];
                }
                elsif ($2 eq 'LLL') {
                    $cldr_hr->{'month_stand_alone_abbreviated'}[ $smhdmyw[4] ];
                }
                elsif (($2 eq 'MM') || ($2 eq 'LL')) {
                    sprintf '%02d', (1 + $smhdmyw[4]);
                }
                elsif (($2 eq 'M') || ($2 eq 'L')) {
                    1 + $smhdmyw[4];
                }

                #date
                elsif ($2 eq 'dd') {
                    sprintf '%02d', $smhdmyw[3];
                }
                elsif ($2 eq 'd') {
                    $smhdmyw[3];
                }

                #hour (12-hour variant)
                elsif (($2 eq 'h') || ($2 eq 'hh')) {
                    $twelve_hrs = $smhdmyw[2];
                    $twelve_hrs -= 12 if $twelve_hrs > 12;
                    $twelve_hrs ||= 12;
                    ($2 eq 'hh') ? sprintf('%02d', $twelve_hrs) : $twelve_hrs;
                }

                #hour (24-hour variant)
                elsif ($2 eq 'H') {
                    $smhdmyw[2];
                }
                elsif ($2 eq 'HH') {
                    sprintf '%02d', $smhdmyw[2];
                }

                #minute
                elsif ($2 eq 'm') {
                    $smhdmyw[1];
                }
                elsif ($2 eq 'mm') {
                    sprintf '%02d', $smhdmyw[1];
                }

                #second
                elsif ($2 eq 's') {
                    $smhdmyw[0];
                }
                elsif ($2 eq 'ss') {
                    sprintf '%02d', $smhdmyw[0];
                }

                #AM/PM
                elsif ($2 eq 'a') {
                    $cldr_hr->{'am_pm_abbreviated'}[ ($smhdmyw[2] < 12) ? 0 : 1 ];
                }

                #weekday - only useful for wider date formats
                elsif ((index($2, 'E') == 0) || (index($2, 'c') == 0)) {
                    my $cldr_wday_num = $smhdmyw[6] ? ($smhdmyw[6] - 1) : 6;

                    if ($2 eq 'EEEE') {
                        $cldr_hr->{'day_format_wide'}[$cldr_wday_num  ];
                    }
                    elsif (($2 eq 'EEE') || ($2 eq 'EE') || ($2 eq 'E')) {
                        $cldr_hr->{'day_format_abbreviated'}[ $cldr_wday_num ];
                    }
                    elsif ($2 eq 'EEEEE') {
                        $cldr_hr->{'day_format_narrow'}[ $cldr_wday_num ];
                    }
                    elsif ($2 eq 'cccc') {
                        $cldr_hr->{'day_stand_alone_wide'}[$cldr_wday_num  ];
                    }
                    elsif (($2 eq 'ccc') || ($2 eq 'cc') || ($2 eq 'c')) {
                        $cldr_hr->{'day_stand_alone_abbreviated'}[ $cldr_wday_num ];
                    }
                    elsif ($2 eq 'ccccc') {
                        $cldr_hr->{'day_stand_alone_narrow'}[ $cldr_wday_num ];
                    }
                }

                #time zone - always UTC
                elsif (($2 eq 'z') || ($2 eq 'zzzz') || ($2 eq 'v') || ($2 eq 'vvvv')) {
                    'UTC';
                }

                #era (e.g., BC/AD) … used in at least one locale (th)
                elsif (($2 eq 'G') || ($2 eq 'GG') || ($2 eq 'GGG')) {
                    $cldr_hr->{'era_abbreviated'}[ $smhdmyw[5] < -1900 ? 0 : 1 ];
                }
                elsif ($2 eq 'GGGGG') {
                    $cldr_hr->{'era_narrow'}[ $smhdmyw[5] < -1900 ? 0 : 1 ];
                }
                elsif ($2 eq 'GGGG') {
                    $cldr_hr->{'era_wide'}[ $smhdmyw[5] < -1900 ? 0 : 1 ];
                }

                else {
                    warn "Unknown CLDR date/time pattern: “$2” ($cldr_pattern)";
                    $2;
                }
            };
    }xgre;
}

1;
