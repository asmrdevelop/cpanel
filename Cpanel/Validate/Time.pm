package Cpanel::Validate::Time;

# cpanel - Cpanel/Validate/Time.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Validate::Time

=head1 SYNOPSIS

    Cpanel::Validate::Time::iso_or_die($supposed_iso8601_date);

    Cpanel::Validate::Time::epoch_or_die($supposed_epoch_time);

=cut

use strict;
use warnings;

use Cpanel::DateUtils ();
use Cpanel::Exception ();

my $ISO_REGEXP = q<
    ([0-9]{4})
    -
    (0[1-9] | 1[0-2])
    -
    (0[1-9] | [12][0-9] | 3[01])
    T
    (?: [01][0-9] | 2[0-3] )
    :
    [0-5][0-9]
    :
    [0-5][0-9]
    Z
>;

#This actually validates a very specific subset of ISO 8601.
sub iso_or_die {
    my $valid = length( $_[0] ) && ( $_[0] =~ m<\A $ISO_REGEXP \z>xo );
    if ( $valid && ( $2 == 2 ) && ( $3 > 28 ) ) {
        my $last_mday = Cpanel::DateUtils::month_last_day( 2, $1 );
        $valid = ( $3 <= $last_mday );
    }

    if ( !$valid ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,ISO 8601] timestamp on this system.', [ $_[0] ] );
    }

    return;
}

sub epoch_or_die {

    # 67767976233521999 is the largest value that will not cause
    # EOVERFLOW on most systems
    #
    # https://stackoverflow.com/questions/11748247/size-of-time-t-and-its-max-value?lq=1
    ( length( $_[0] ) && $_[0] !~ tr<0-9><>c && $_[0] <= 67767976233521999 ) or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,UNIX] epoch timestamp.', [ $_[0] ] );
    };

    return;
}

1;
