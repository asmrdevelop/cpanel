package Whostmgr::Transfers::Session::Items::AccountUpload;

# cpanel - Whostmgr/Transfers/Session/Items/AccountUpload.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# We want to removed uploaded cpmove files after the restore
# so we use AccountRemoteBase
use base 'Whostmgr::Transfers::Session::Items::AccountRemoteBase';

sub transfer {
    my ($self) = @_;

    my $cpmovefile = $self->{'input'}->{'cpmovefile'};
    print $self->_locale()->maketext( "You have successfully uploaded the file “[_1]”.", $cpmovefile ) . "\n";

    return $self->success();
}

sub is_transfer_item {
    return 0;
}

1;
