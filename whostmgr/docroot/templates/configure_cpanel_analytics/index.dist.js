/*
 * index.dist.js                                      Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

// Loads the application with the pre-built combined files
require( ["frameworksBuild", "locale!cjtBuild", "app/index.cmb"], function() {
    "use strict";

    require(
        [
            "app/index"
        ],
        function(APP) {
            APP();
        }
    );
});
