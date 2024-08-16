/*
# templates/mod_security/config.dist.js           Copyright(c) 2015cPanel, Inc.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the pre-built combined files
require( ["frameworksBuild", "locale!cjtBuild", "locale!app/config.cmb"], function() {
    require(
        [
            "app/config"
        ],
        function(APP) {
            APP();
        }
    );
});
