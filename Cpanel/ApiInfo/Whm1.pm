package Cpanel::ApiInfo::Whm1;

# cpanel - Cpanel/ApiInfo/Whm1.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(Cpanel::ApiInfo);

sub SPEC_FILE_BASE { return 'whm_v1.dist' }

#
# Whm1 api is not modular so these can only be done on the build
# machines leaving the real api collection functionality in Cpanel::ApiInfo::Dist::Whm1
#
sub _get_public_data_from_datastore {
    my ( $self, $ds_data ) = @_;

    return $ds_data->get_data()->{'functions'};
}

1;
