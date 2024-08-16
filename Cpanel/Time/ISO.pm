package Cpanel::Time::ISO;

# cpanel - Cpanel/Time/ISO.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug      ();
use Cpanel::LoadModule ();

=encoding utf-8

=head1 NAME

Cpanel::Time::ISO - time format as per ISO 8601

=head1 SYNOPSIS

    $isotime = unix2iso();  #uses current time
    $isotime = unix2iso( $some_timestamp );

    $epoch = iso2unix($isotime);

    #Special-use:
    unix2iso_date( $some_timestamp );
    unix2iso_time( $some_timestamp );

=head1 DESCRIPTION

ISO 8601 describes a useful format for representing times as strings.
This module translates between that format and epoch seconds.

Note that, for now, the only ISO time format returned or accepted is:

    yyyy-mm-ddThh:mm::ssZ

=head1 FUNCTIONS

=head2 $iso = unix2iso( OPTIONAL_TIMESTAMP )

Returns ISO time for the given timestamp; if no timestamp is given,
current system time is used.

=cut

sub unix2iso {
    Cpanel::LoadModule::load_perl_module('Cpanel::Time') unless $INC{'Cpanel/Time.pm'};
    return sprintf( '%04d-%02d-%02dT%02d:%02d:%02dZ', reverse( ( Cpanel::Time::gmtime( $_[0] || time() ) )[ 0 .. 5 ] ) );
}

=head2 $epoch = iso2unix( ISO_TIME )

Returns epoch seconds for a given ISO time. The ISO time must conform to the
format shown in the DESCRIPTION section above.

=cut

sub iso2unix {
    my ($iso_time) = @_;

    if ( rindex( $iso_time, 'Z' ) != length($iso_time) - 1 ) {
        die "Only UTC times, not “$iso_time”!";
    }

    my @smhdmy = reverse split m<[^0-9.]>, $iso_time;
    Cpanel::LoadModule::load_perl_module('Cpanel::Time') unless $INC{'Cpanel/Time.pm'};

    return Cpanel::Time::timegm(@smhdmy);
}

=head1 SPECIAL-USE FUNCTIONS

These B<will> be removed, so please don’t use them unless you really need
them.  These have only been left in to accomodate old templates.

=head2 unix2iso_date( TIMESTAMP )

Like C<unix2iso()>, except only the date
portion of the time (e.g., C<2017-07-03> is returned. This is useful for
contexts when localized date formatting is too slow.

=cut

sub unix2iso_date {
    Cpanel::LoadModule::load_perl_module('Cpanel::Time') unless $INC{'Cpanel/Time.pm'};
    Cpanel::Debug::log_deprecated('This function will be removed, please use locale datetime');

    return sprintf( '%04d-%02d-%02d', reverse( ( Cpanel::Time::gmtime( $_[0] || time() ) )[ 3 .. 5 ] ) );
}

=head2 unix2iso_date( TIMESTAMP )

Like C<unix2iso_date()>, but it only returns the time of day, exclusive of the
trailing C<Z>, e.g., C<14:02:06>.

=cut

sub unix2iso_time {
    Cpanel::LoadModule::load_perl_module('Cpanel::Time') unless $INC{'Cpanel/Time.pm'};
    Cpanel::Debug::log_deprecated('This function will be removed, please use locale datetime');
    return sprintf( '%02d:%02d:%02d', reverse( ( Cpanel::Time::gmtime( $_[0] || time() ) )[ 0 .. 2 ] ) );
}

1;
