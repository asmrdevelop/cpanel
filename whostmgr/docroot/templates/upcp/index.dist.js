/*
# templates/upcp/index.dist.js                    Copyright(c) 2020 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the pre-built combined files
require(["frameworksBuild", "locale!cjtBuild", "app/index.cmb"], function() {
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