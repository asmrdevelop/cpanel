/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/constants.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(["cjt/util/locale"], function(LOCALE) {
    "use strict";

    var DEFAULT_PRIMARY_DARK = "#08193E";  // $cp-midnight-express from /usr/local/cpanel/base/frontend/jupiter/base_styles/00_configuration/_cp_colors.scss
    var DEFAULT_PRIMARY_LIGHT = "#ffffff"; // $cp-white            from /usr/local/cpanel/base/frontend/jupiter/base_styles/00_configuration/_cp_colors.scss

    return {

        // Image
        EMBEDDED_SVG: "data:image/svg+xml;base64,",
        EMBEDDED_ICO: "data:image/x-icon;base64,",
        DATA_URL_PREFIX_REGEX: /^data:[^,]*,/,

        // Colors - It would be nice to figure out a way to load these from the scss file, but I cant see a good way without
        DEFAULT_PRIMARY_DARK: DEFAULT_PRIMARY_DARK,
        DEFAULT_PRIMARY_LIGHT: DEFAULT_PRIMARY_LIGHT,
        DEFAULT_COLORS: {
            primary: DEFAULT_PRIMARY_DARK,
        },

        // File upload sizes
        MAX_FILE_SIZE: 100 * 1000,  // 100 kilobytes

        // Tabs
        GENERAL_TABS_INFO: {
            logos: LOCALE.maketext("Logos"),
            colors: LOCALE.maketext("Colors"),
            favicon: LOCALE.maketext("Favicon"),
            links: LOCALE.maketext("Links"),
            "public-contact": LOCALE.maketext("Public Contact"),
        },

        JUPITER_TAB_ORDER: [
            "logos",
            "colors",
            "favicon",
            "links",
            "public-contact",
        ],

        JUPITER_TAB_INDEX: {
            "logos": 3,
            "colors": 4,
            "favicon": 5,
            "links": 6,
            "public-contact": 10,
        },

        // Routing
        DEFAULT_THEME: "jupiter",
        DEFAULT_ROUTE: "logos",
    };
});
