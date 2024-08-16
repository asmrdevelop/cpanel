/*
# mail/authentication/manage.dist.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W098 */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "app/manage.cmb"
], function() {
    "use strict";
    require(["cjt/startup"], function(STARTUP) {
        STARTUP.startApplication("app/manage");
    });
});
