/*
# mail/csv/csvimport-step4.dist.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the pre-built combined files
require( [
    "frameworksBuild",
    "locale!cjtBuild"
], function() {
    "use strict";
    require(["cjt/startup"], function(STARTUP) {
        STARTUP.startApplication([
            "app/csv/csvimport-step4"
        ]);
    });
});
