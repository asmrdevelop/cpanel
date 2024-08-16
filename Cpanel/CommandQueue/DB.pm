package Cpanel::CommandQueue::DB;

# cpanel - Cpanel/CommandQueue/DB.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(
  Cpanel::CommandQueue
);

sub new {
    my ( $class, $dbh ) = @_;

    die "Need DB handle!" if !$dbh;

    my $self = $class->SUPER::new();
    $self->{'_dbh'} = $dbh;

    return $self;
}

sub _convert_cmd_to_coderef {
    my ( $self, $undo ) = @_;

    if ( !ref $undo ) {
        return sub { $self->{'_dbh'}->do($undo) };
    }

    return $self->SUPER::_convert_cmd_to_coderef($undo);
}

1;
