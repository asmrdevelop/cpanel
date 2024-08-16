package Cpanel::HTTP::Date::Tiny;

#
#This software is copyright (c) 2016 by Christian Hansen.
#
#This is free software; you can redistribute it and/or modify it under
#the same terms as the Perl 5 programming language system itself.
#

use strict;
use warnings;

use Time::Local ();

# Date conversions adapted from HTTP::Tiny and HTTP::Date
my $MoY = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec";

sub parse_http_date {
    my @tl_parts;
    if ( $_[0] =~ /^[SMTWF][a-z]+, +(\d{1,2}) ($MoY) +(\d\d\d\d) +(\d\d):(\d\d):(\d\d) +GMT$/o ) {
        @tl_parts = ( $6, $5, $4, $1, ( index( $MoY, $2 ) / 4 ), $3 );
    }
    elsif ( $_[0] =~ /^[SMTWF][a-z]+, +(\d\d)-($MoY)-(\d{2,4}) +(\d\d):(\d\d):(\d\d) +GMT$/o ) {
        @tl_parts = ( $6, $5, $4, $1, ( index( $MoY, $2 ) / 4 ), $3 );
    }
    elsif ( $_[0] =~ /^[SMTWF][a-z]+ +($MoY) +(\d{1,2}) +(\d\d):(\d\d):(\d\d) +(?:[^0-9]+ +)?(\d\d\d\d)$/o ) {
        @tl_parts = ( $5, $4, $3, $2, ( index( $MoY, $1 ) / 4 ), $6 );
    }
    return eval {
        my $t = @tl_parts ? Time::Local::timegm(@tl_parts) : -1;
        $t < 0 ? undef : $t;
    };
}

1;
