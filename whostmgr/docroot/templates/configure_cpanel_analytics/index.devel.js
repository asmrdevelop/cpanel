/*
 * index.devel.js                                     Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

// Loads the application with the non-combined files
require(
    [
        "app/index"
    ],
    function(APP) {
        "use strict";

        APP();
    }
);
