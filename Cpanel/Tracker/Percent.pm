package Cpanel::Tracker::Percent;

# cpanel - Cpanel/Tracker/Percent.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base 'Cpanel::Tracker::Base';

use Cpanel::TimeHiRes ();
use Cpanel::Exception ();

my $ONE_MiB = 1024**2;

sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', ['content_length'] ) if !$OPTS{'content_length'};

    my $self = {
        'content_length'             => $OPTS{'content_length'},
        'total_bytes_read'           => 0,
        'percent'                    => 0,
        '_last_tracker_update_bytes' => 0,
        '_start_time'                => Cpanel::TimeHiRes::time(),
        '_original_start_time'       => Cpanel::TimeHiRes::time(),
        '_end_time'                  => 0,
    };
    return bless $self, $class;
}

sub _display_tracker {
    my ($self) = @_;

    $self->{'_end_time'} = Cpanel::TimeHiRes::time();

    my $bytes_per_second = sprintf( '%.2f', ( $self->{'total_bytes_read'} - $self->{'_last_tracker_update_bytes'} ) / ( ( $self->{'_end_time'} - $self->{'_start_time'} ) || 0.0001 ) );

    $self->{'_last_tracker_update_bytes'} = $self->{'total_bytes_read'};
    $self->{'_start_time'}                = $self->{'_end_time'};

    print( '…' . $self->{'percent'} . '% @ ' . sprintf( '%0.4f', ( $bytes_per_second / $ONE_MiB ) ) . " MiB/s …\n" );

    return 1;
}

sub add_bytes {
    my ( $self, $bytes ) = @_;

    $self->{'total_bytes_read'} += $bytes;

    my $new_percent = sprintf( '%.0f', ( $self->{'total_bytes_read'} / $self->{'content_length'} * 100 ) );

    if ( $new_percent != $self->{'percent'} ) {
        $self->{'percent'} = $new_percent;
        $self->_display_tracker();

    }

    return $bytes;
}

1;
