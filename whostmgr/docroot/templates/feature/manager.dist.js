/*
# templates/feature/manager.dist.js               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the pre-built combined files
require( ["frameworksBuild", "locale!cjtBuild", "locale!app/manager.cmb"], function() {
    require(
        [
            "app/manager"
        ],
        function(APP) {
            APP();
        }
    );
});