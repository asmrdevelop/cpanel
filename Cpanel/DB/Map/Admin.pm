package Cpanel::DB::Map::Admin;

# cpanel - Cpanel/DB/Map/Admin.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#NOTE: A mix-in class.

use strict;

use parent qw( Cpanel::DB::Map::Named );

use Cpanel::DB::Utils ();

sub update_cpuser_name {
    my ( $self, $newname ) = @_;

    $self->{'cpuser'} = $newname;

    $self->name( Cpanel::DB::Utils::username_to_dbowner($newname) );

    return;
}

sub cpuser {
    my ($self) = @_;
    return $self->{'cpuser'};
}

1;
