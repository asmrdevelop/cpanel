package Cpanel::Time::HTTP;

# cpanel - Cpanel/Time/HTTP.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Not for production
#use strict;
#use warnings;

my @weekday = qw/Sun Mon Tue Wed Thu Fri Sat/;
my @longday = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
my @month   = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

#RFC 2616 3.3.1
sub time2http {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday ) = gmtime( $_[0] || time() );
    return sprintf( '%s, %02d %s %04d %02d:%02d:%02d GMT', $weekday[$wday], $mday, $month[$mon], $year + 1900, $hour, $min, $sec );
}

sub time2cookie {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday ) = gmtime( $_[0] || time() );
    return sprintf( '%s, %02d-%s-%d %02d:%02d:%02d GMT', $weekday[$wday], $mday, $month[$mon], $year + 1900, $hour, $min, $sec );
}

1;
