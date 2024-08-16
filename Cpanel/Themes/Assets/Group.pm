package Cpanel::Themes::Assets::Group;

# cpanel - Cpanel/Themes/Assets/Group.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use parent q{Cpanel::Themes::Assets::Base};

sub attributes {
    return {
        'order' => {
            'validator' => qr/^[0-9-]+$/,
            'required'  => 1,
        },
        'id' => {

            # If this one changes, please update the one in get_app_list_order in Cpanel::Branding
            'validator' => qr/^[0-9a-z_-]+$/i,
            'required'  => 1,
        },
        'name' => {
            'required' => 1,
        },
        'icon' => {},
    };
}

1;
