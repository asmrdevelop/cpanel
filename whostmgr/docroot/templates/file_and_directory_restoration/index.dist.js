/*
# file_and_directory_restoration/index.dist.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the pre-built combined files
require([
    "frameworksBuild",
    "locale!cjtBuild",
    "locale!app/index.cmb"
],
function() {
    "use strict";
    require(
        [
            "cjt/startup"
        ],
        function(STARTUP) {
            STARTUP.startApplication();
        }
    );
}
);
