package Cpanel::Tracker::Base;

# cpanel - Cpanel/Tracker/Base.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub finish {
    my ($self) = @_;

    $self->{'_start_time'}                = $self->{'_original_start_time'};
    $self->{'_last_tracker_update_bytes'} = 0;

    $self->_display_tracker();

    return 1;
}
1;
