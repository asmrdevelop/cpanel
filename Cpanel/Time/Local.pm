package Cpanel::Time::Local;

# cpanel - Cpanel/Time/Local.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# Not for production
#use warnings;

our $server_offset_string;
our ( $timecacheref, $localtimecacheref ) = ( [ -1, '', -1 ], [ -1, '', -1 ] );

my $server_offset;
my $localtime_link_or_mtime;
our $ETC_LOCALTIME = q{/etc/localtime};

#for testing
sub _clear_caches {
    undef $_
      for (
        $server_offset,
        $server_offset_string,
        $timecacheref,
        $localtimecacheref,
        $localtime_link_or_mtime,
      );
    return;
}

sub localtime2timestamp {
    my ( $time, $delimiter ) = @_;
    $delimiter ||= ' ';
    $time      ||= time();

    # If we have a buildup of log messages in the same second it will drive the cpu time up just calculating the time
    # instead we can just cache it
    return $localtimecacheref->[2] if $localtimecacheref->[0] == $time && $localtimecacheref->[1] eq $delimiter;

    my $tz_offset = get_server_offset_as_offset_string($time);

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime $time;
    @{$localtimecacheref}[ 0, 1 ] = ( $time, $delimiter );
    return ( $localtimecacheref->[2] = sprintf( '%04d-%02d-%02d' . $delimiter . '%02d:%02d:%02d %s', $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $tz_offset ) );
}

sub get_server_offset_as_offset_string {
    my ($time_supplied) = @_;

    # auto purge cache when we detect a change in /etc/localtime
    if ( !$time_supplied ) {
        my $link_or_mtime;
        if ( -l $ETC_LOCALTIME ) {
            $link_or_mtime = readlink($ETC_LOCALTIME);
        }
        else {
            $link_or_mtime = ( stat($ETC_LOCALTIME) )[9];
        }
        if ( defined $link_or_mtime ) {
            $localtime_link_or_mtime ||= $link_or_mtime;

            # also detects if the file become a symlink or a hardlink
            if ( $localtime_link_or_mtime ne $link_or_mtime ) {
                _clear_caches();
                $localtime_link_or_mtime = $link_or_mtime;
            }
        }
    }

    if ( $time_supplied || !defined $server_offset_string ) {

        #We need to be sure that the localtime() and gmtime() below
        #occur within the same clock second.
      UNTIL_SAME_SECOND: {
            my $starttime = time();
            my $time      = $time_supplied || $starttime;
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday ) = localtime $time;

            # Generate a timezone string without calling POSIX::strftime.
            my ( $gmmin, $gmhour, $gmyear, $gmyday ) = ( gmtime($time) )[ 1, 2, 5, 7 ];

            redo UNTIL_SAME_SECOND if time != $starttime;

            # Unfortunately, the offset isn't as trivial as we would hope.
            #  - Not all timezones are offset by integral hours (need minutes to offset correctly)
            #  - The simple subtraction went nuts near midnight, because GMT and local time are
            #    on different days. The last term moves by number of minutes in a day in that case.
            my $yday_offset;
            if ( $year == $gmyear ) {
                $yday_offset = ( $yday <=> $gmyday );
            }
            elsif ( $year < $gmyear ) {
                $yday_offset = -1;
            }
            elsif ( $year > $gmyear ) {
                $yday_offset = 1;
            }

            my $gmoffset      = ( $hour * 60 + $min ) - ( $gmhour * 60 + $gmmin ) + 1440 * $yday_offset;
            my $offset_string = sprintf( '%+03d%02d', int( $gmoffset / 60 ), $gmoffset % 60 );
            if ($time_supplied) {
                return $offset_string;
            }
            else {
                $server_offset_string = $offset_string;
            }
        }
    }
    return $server_offset_string;
}

sub get_server_offset_in_seconds {
    if ( !defined $server_offset ) {
        if ( get_server_offset_as_offset_string() =~ m/([-+]?[0-9]{2})([0-9]{2})/ ) {
            my ( $hours, $minutes ) = ( $1, $2 );
            my $seconds = ( ( abs($hours) * 60 * 60 ) + ( $minutes * 60 ) );
            $server_offset = $hours < 0 ? "-$seconds" : $seconds;
        }
        else {

            # ? warn("get_server_offset_as_offset_string() seems broken!!") ?
            $server_offset = 0;
        }
    }
    return $server_offset;
}

1;
