package Cpanel::Template::Plugin::CPDate;

# cpanel - Cpanel/Template/Plugin/CPDate.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet safe here

use base 'Template::Plugin';

use Time::Local ();

use Cpanel::CLDR::DateTime ();
use Cpanel::Locale         ();
use Cpanel::LoadModule     ();
use Whostmgr::DateTime     ();

our @months = qw(
  January
  February
  March
  April
  May
  June
  July
  August
  September
  October
  November
  December
);

sub new {
    my ( $class, $context ) = @_;
    return bless {
        '_CONTEXT' => $context,
        'months'   => \@months,
    }, $class;
}

sub whm_format_date {
    shift;
    return scalar Whostmgr::DateTime::format_date(@_);
}

sub iso_format {
    shift;
    return Whostmgr::DateTime::iso_format(@_);
}

#XXX: NOT localized. Do not use.
sub get_text_month {
    shift;
    my $i = shift;
    if ( 1 > $i || 12 < $i ) {
        $i = 1;
    }
    $i--;
    return $months[$i];
}

#FROM whostmgr2.pl
sub nicedate {
    shift;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = CORE::localtime(shift);

    return [ $year + 1900, map { sprintf( '%02d', $_ ) } ( $mon + 1, $mday, $hour, $min, $sec ) ];
}

# Format the timestamp as a human readable date.
sub localtime { shift(); return scalar CORE::localtime( shift() ); }

sub localtime_parts { shift(); return [ CORE::localtime( shift() ) ]; }

#Args can be a list or a single arrayref.
#
#NOTE: 0-indexed months.
#
sub timegm {
    my @args = 'ARRAY' eq ref $_[1] ? @{ $_[1] } : @_[ 1 .. $#_ ];
    return Time::Local::timegm(@args);
}

#Same as Time::Local::timelocal() but sets a specific timezone first.
#
#Args:
#
#   - a timezone
#
#   - the arg list for timelocal(), either as a list or a single arrayref
#
#NOTE: 0-indexed months.
#
sub timezone_timelocal {
    shift;

    my ($tz) = shift;
    local $ENV{'TZ'} = $tz || $ENV{'TZ'};

    my @args = 'ARRAY' eq ref $_[0] ? @{ $_[0] } : @_;

    return Time::Local::timelocal(@args);
}

#returns a string corresponding to the localized ymd order: mdy, ymd, etc.
#TODO: Get the yMd field from CLDR, and return an altered version of that,
#instead of this "roundabout" way of doing things.
my $_cached_ymd;

sub ymd_order {
    return $_cached_ymd if $_cached_ymd;

    my $ts = Time::Local::timegm( 0, 0, 0, 1, 3, 2007 );    #1 April 2007

    my $localized = Cpanel::Locale->get_handle()->datetime( $ts, 'date_format_short' );
    my %order     = (
        d => index( $localized, '1' ),
        m => index( $localized, '4' ),
        y => index( $localized, '7' ),
    );

    return $_cached_ymd = join( q{}, ( sort { $order{$a} <=> $order{$b} } ( keys %order ) ) );
}

#for testing
sub _reset_ymd_order_cache {
    undef $_cached_ymd;
}

sub ymd_words {
    my $ymd    = ymd_order();
    my $locale = Cpanel::Locale->get_handle();

    my %convert = (
        y => $locale->maketext('year'),
        m => $locale->maketext('Month'),
        d => $locale->maketext('day of month'),
    );

    my @ymd = map { $convert{$_} } split( m{}, $ymd );

    return wantarray ? @ymd : \@ymd;
}

sub add_local_interval {
    shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::DateUtils');
    goto &Cpanel::DateUtils::add_local_interval;
}

sub local_startof {
    shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::DateUtils');
    goto &Cpanel::DateUtils::local_startof;
}

sub day_stand_alone_wide {
    return Cpanel::CLDR::DateTime::day_stand_alone_wide();
}

sub day_stand_alone_abbreviated {
    return Cpanel::CLDR::DateTime::day_stand_alone_abbreviated();
}

sub month_stand_alone_wide {
    return Cpanel::CLDR::DateTime::month_stand_alone_wide();
}

sub month_stand_alone_abbreviated {
    return Cpanel::CLDR::DateTime::month_stand_alone_abbreviated();
}

1;
