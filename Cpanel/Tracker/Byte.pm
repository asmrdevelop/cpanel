package Cpanel::Tracker::Byte;

# cpanel - Cpanel/Tracker/Byte.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::TimeHiRes ();

use base 'Cpanel::Tracker::Base';

my $ONE_MiB = 1024**2;
our $UPDATE_INTERVAL = 10;

sub new {
    my ($class) = @_;

    my $self = {
        'total_bytes_read'           => 0,
        '_last_tracker_update_bytes' => 0,
        '_original_start_time'       => Cpanel::TimeHiRes::time(),
        '_start_time'                => Cpanel::TimeHiRes::time(),
        '_end_time'                  => 0,
    };
    return bless $self, $class;
}

sub _display_tracker {
    my ($self) = @_;

    $self->{'_end_time'} = Cpanel::TimeHiRes::time();

    my $bytes_per_second = sprintf( '%.2f', ( $self->{'total_bytes_read'} - $self->{'_last_tracker_update_bytes'} ) / ( ( $self->{'_end_time'} - $self->{'_start_time'} ) || 0.0001 ) );

    $self->{'_last_tracker_update_bytes'} = $self->{'total_bytes_read'};

    $self->{'_start_time'} = $self->{'_end_time'};

    print( '…' . $self->{'total_bytes_read'} . ' bytes @ ' . sprintf( "%0.4f", $bytes_per_second / $ONE_MiB ) . " MiB/s …\n" );

    return 1;
}

sub add_bytes {
    my ( $self, $bytes ) = @_;

    $self->{'total_bytes_read'} += $bytes;

    # Only display every $UPDATE_INTERVAL seconds
    if ( time() - $UPDATE_INTERVAL > $self->{'_start_time'} ) {

        $self->_display_tracker();
    }

    return $bytes;
}

1;
