package Cpanel::Time;

# cpanel - Cpanel/Time.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub time2datetime {
    my $time      = shift || time();
    my $delimiter = shift;
    $delimiter = ' ' unless defined $delimiter;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime $time;
    return sprintf( '%04d-%02d-%02d' . $delimiter . '%02d:%02d:%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
}

sub time2dnstime {
    my $time = shift || time();
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime $time;
    return sprintf( '%04d%02d%02d', $year + 1900, $mon + 1, $mday );
}

sub time2condensedtime {
    my $time = shift || time();
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime $time;
    return sprintf( '%04d%02d%02d%02d%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
}

#----------------------------------------------------------------------
# Convenience functions that relieve the frequent annoyance of
# 0-indexed months and 1900-as-first-year from Perl’s time functions.
#----------------------------------------------------------------------

#cf. perldoc -f localtime
my $PERL_TIME_MONTH_OFFSET = 1;
my $PERL_TIME_YEAR_OFFSET  = 1900;

#NOTE: localtime(undef) is the same as localtime(0), NOT localtime().
#
sub localtime {
    my @args = @_;

    if ( !wantarray ) {
        return @args ? localtime( $args[0] ) : localtime;
    }

    my @res = @args ? ( localtime $args[0] ) : (localtime);

    return _humanize_split_time(@res);
}

sub gmtime {
    if ( !wantarray ) {
        return @_ ? gmtime( $_[0] ) : gmtime;
    }

    return _humanize_split_time( @_ ? ( gmtime $_[0] ) : (gmtime) );
}

sub timelocal {
    require Time::Local;
    no warnings 'redefine';
    *timelocal = \&_real_timelocal;
    goto &_real_timelocal;
}

sub timegm {
    require Time::Local;
    no warnings 'redefine';
    *timegm = \&_real_timegm;
    goto &_real_timegm;
}

sub _humanize_split_time {
    return (
        @_[ 0 .. 3 ],
        $_[4] + $PERL_TIME_MONTH_OFFSET,
        $_[5] + $PERL_TIME_YEAR_OFFSET,
        @_[ 6 .. $#_ ],
    );
}

sub _dehumanize_smhdmy {
    my (@smhdmy) = @_;

    $smhdmy[4] -= $PERL_TIME_MONTH_OFFSET;

    #NOTE: perldoc Time::Local for why we don’t alter the year here.
    if ( $smhdmy[5] < 1000 ) {
        die "Time::Local can’t represent years prior to 1000 A.D.";
    }

    return @smhdmy;
}

sub _real_timelocal {
    my (@smhdmy) = @_;

    return Time::Local::timelocal( _dehumanize_smhdmy(@smhdmy) );
}

sub _real_timegm {
    my (@smhdmy) = @_;

    return Time::Local::timegm( _dehumanize_smhdmy(@smhdmy) );
}

1;
