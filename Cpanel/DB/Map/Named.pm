package Cpanel::DB::Map::Named;

# cpanel - Cpanel/DB/Map/Named.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#NOTE: A mix-in class.

use strict;
use warnings;

sub name {
    my ( $self, $name ) = @_;

    if ( defined($name) && !length($name) ) {
        die "Empty-string name() not allowed for $self!";
    }

    $self->{'name'} = $name if length $name;
    return $self->{'name'};
}

1;
