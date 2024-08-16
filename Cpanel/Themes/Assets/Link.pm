package Cpanel::Themes::Assets::Link;

# cpanel - Cpanel/Themes/Assets/Link.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent q{Cpanel::Themes::Assets::Base};

sub attributes {
    return {
        # int indicating the order weight of the link, highest = end of list
        'order' => {
            'validator' => qr/^-?[0-9]+$/,
            'required'  => 1,
        },

        # ID of the link, used for unique identification
        # best practice here is to do all lowercase, but x3 doesn't do that.
        'id' => {
            'validator' => qr/^[0-9a-z_-]+$/i,
            'required'  => 1,
        },

        # Display name of the link in the interface
        'name' => {
            'required' => 1,
        },

        # path to the icon as it exists on disk, perhaps validator should be a -e check?
        'icon' => {
            'required' => 1,
        },

        # what feature is actually being implemented here
        'implements' => {
            'validator' => qr/^[0-9a-z_-]+$/i,
        },

        # group ID
        'group_id' => {
            'validator' => qr/^[0-9a-z_-]+$/i,
            'required'  => 1,
        },

        # the path that we're linking to
        'uri' => {
            'validator' => qr/^.+$/,
        },

        # the target window for the uri
        'target' => {
            'validator' => qr/^[0-9a-z-_]*$/i,
        },

        # extra stuff (not the href) inside of the A tag
        'a_contents' => {
            'validator' => qr/^.+$/,
        },

        # feature to display whether it should be displayed or not
        'feature' => {},

        # cpanelif statement determining display (see: https://go.cpanel.net/guidetovariables)
        'if' => {},

        # base64_png_image
        'base64_png_image' => {},

        # search text to be used for full text filtering of nav
        'search_text' => {},

        # whether the feature should be added to feature manager
        'featuremanager' => {}
    };
}

1;
