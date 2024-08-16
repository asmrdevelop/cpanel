package Cpanel::DateUtils;

# cpanel - Cpanel/DateUtils.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use Try::Tiny;
use Cpanel::LoadModule ();

our $VERSION = '0.0.3';

my %months = do {
    my $i = 0;
    map { $_ => ++$i } qw/jan feb mar apr may jun jul aug sep oct nov dec/;
};

my @days_in = ( undef, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

sub month_num {
    my ($month) = @_;
    return unless defined $month;
    return $month if $month =~ /^\d+$/;
    $month = lc substr( $month, 0, 3 );
    return unless exists $months{$month};
    return $months{$month};
}

#1-indexed months
#
sub month_last_day {
    my ( $mon, $yr ) = @_;

    if ( 2 == $mon && 0 == ( $yr % 4 ) ) {
        if ( !( 0 == ( $yr % 100 ) ) || ( 0 == ( $yr % 400 ) ) ) {
            return $days_in[$mon] + 1;
        }
    }

    return ( $days_in[$mon] || die "Invalid month index: $mon" );
}

sub days_til_month_end {
    my ($time) = @_;
    my ( $month, $year ) = ( localtime($time) )[ 4, 5 ];
    if ( ++$month == 12 ) {
        $month = 0;
        ++$year;
    }
    Cpanel::LoadModule::load_perl_module('Time::Local') if !$INC{'Time/Local.pm'};
    my $begin_next_month = Time::Local::timelocal( 0, 0, 0, 1, $month, $year );
    return ( $begin_next_month - $time ) / 86400;
}

sub time_til_month_end {
    my ($time) = @_;
    my ( $month, $year ) = ( localtime($time) )[ 4, 5 ];
    if ( ++$month == 12 ) {
        $month = 0;
        ++$year;
    }
    Cpanel::LoadModule::load_perl_module('Time::Local') if !$INC{'Time/Local.pm'};
    my $begin_next_month = Time::Local::timelocal( 0, 0, 0, 1, $month, $year );
    return $begin_next_month - $time;
}

#for testing
sub _now { return time }

sub timestamp_is_in_this_month {
    my ($time) = @_;

    my ( $month, $year )  = ( localtime $time )[ 4, 5 ];
    my ( $thism, $thisy ) = ( localtime _now() )[ 4, 5 ];

    return 0 if $month != $thism;
    return 0 if $year != $thisy;

    return 1;
}

sub get_last_second_of_ymdhm {
    my ( $year, $month, $day, $hour, $minute ) = @_;

    die 'Need year!' if !$year;

    Cpanel::LoadModule::load_perl_module('Cpanel::Time') if !$INC{'Cpanel/Time.pm'};
    if ( defined $minute ) {
        return Cpanel::Time::timelocal( 59, $minute, $hour, $day, $month, $year );
    }

    if ( defined $hour ) {
        return Cpanel::Time::timelocal( 59, 59, $hour, $day, $month, $year );
    }

    my $is_last_of_month;

    if ($day) {
        die 'Need month if day!' if !$month;

        return Cpanel::Time::timelocal( 59, 59, 23, $day, $month, $year );
    }
    else {
        $is_last_of_month = 1;
    }

    if ( defined($month) && $month < 12 ) {
        if ($is_last_of_month) {
            return Cpanel::Time::timelocal( 0, 0, 0, 1, $month + 1, $year ) - 1;
        }
    }

    return Cpanel::Time::timelocal( 0, 0, 0, 1, 1, $year + 1 ) - 1;
}

my @smhdmy = qw(
  second
  minute
  hour
  day
  month
  year
);
my %unit_index = map { $smhdmy[$_] => $_ } ( 0 .. $#smhdmy );

sub add_local_interval {
    my ( $time, $count, $unit, $timezone ) = @_;

    local $ENV{'TZ'} = $timezone if length $timezone;

    require DateTime;
    my $dt = DateTime->from_epoch(
        'epoch' => $time,
        ( length $timezone ? ( time_zone => $timezone ) : () )
    );
    try {
        $dt->add( "${unit}s" => $count );
    }
    catch {
        # We switch to UTC and then back because in the time zone in question,
        # the date we tried to create doesn't exist (e.g. because of Daylight
        # Saving Time).  This isn't optimal, but it gives us the closest thing
        # possible.
        $dt->set_time_zone('UTC');
        $dt->add( "${unit}s" => $count );
        $dt->set_time_zone($timezone) if length $timezone;
    };
    return $dt->epoch;
}

#returns the “start of” the month/hour/etc. in which $time happens.
#
#cf. moment.js’s startOf() method
#
sub local_startof {
    my ( $time, $unit, $timezone ) = @_;

    local $ENV{'TZ'} = $timezone if length $timezone;

    Cpanel::LoadModule::load_perl_module('Time::Local')  if !$INC{'Time/Local.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::Time') if !$INC{'Cpanel/Time.pm'};
    return _startof(
        $time, $unit,
        \&Cpanel::Time::localtime,
        \&Cpanel::Time::timelocal,
    );
}

sub _startof {
    my ( $time, $unit, $splitter_cr, $packer_cr ) = @_;

    my @split = ( $splitter_cr->($time) )[ 0 .. 5 ];

    my $index = $unit_index{$unit} - 1;
    die "Invalid unit: “$unit”" if !length $index || $index < 0;

    for my $i ( 0 .. $index ) {
        if ( $i == 3 || $i == 4 ) {
            $split[$i] = 1;
        }
        else {
            $split[$i] = 0;
        }
    }

    return $packer_cr->(@split);
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::DateUtils - A few utility functions for manipulating dates

=head1 VERSION

This document describes Cpanel::DateUtils version 0.0.3

=head1 SYNOPSIS

    use Cpanel::DateUtils;

    my $num = month_num( 'January' );
    my $last = month_last_day( 2, 2008 );


=head1 DESCRIPTION

Working with dates can often require a few utilities to make work somewhat
easier. This modules serves to collect those utilities so they don't end up
proliferating through the code.

=head1 INTERFACE

=head2 Cpanel::DateUtils::month_num( $month )

Converts a month name (or 3 letter abbreviation) to a number between 1 and 12.

Returns C<undef> if the argument is missing or if the supplied month name is not
recognizable.

=head2 Cpanel::DateUtils::month_last_day( $month, $year )

Retrieve the last day of the month given a month and year.

=head2 Cpanel::DateUtils::days_til_month_end( $time )

Return the number of days (as a decimal number) from C<$time> to the end of the
month containing C<$time>.

=head2 Cpanel::DateUtils::time_til_month_end( $time )

Return the number of seconds (as a decimal number) from C<$time> to the end of the
month containing C<$time>.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::DateUtils requires no configuration files or environment variables.

=head1 DEPENDENCIES

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
