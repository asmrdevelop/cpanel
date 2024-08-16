/*
# security/tls_wizard/index.dist.js                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "app/index.cmb"
], function() {
    "use strict";
    require(["cjt/startup"], function(STARTUP) {
        STARTUP.startApplication();
    });
});
