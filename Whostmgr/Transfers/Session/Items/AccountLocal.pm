package Whostmgr::Transfers::Session::Items::AccountLocal;

# cpanel - Whostmgr/Transfers/Session/Items/AccountLocal.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Whostmgr::Transfers::Session::Items::AccountBase';

sub transfer {
    my ($self) = @_;

    my $cpmovefile = $self->{'input'}->{'cpmovefile'};
    print $self->_locale()->maketext( "Setup “[_1]”: success!", $cpmovefile ) . "\n";

    return $self->success();
}

sub is_transfer_item {
    return 0;
}

1;
