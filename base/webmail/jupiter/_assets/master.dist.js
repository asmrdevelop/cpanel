/*
# cpanel - base/webmail/jupiter/_assets/master.dist.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "master/master.cmb",
], function() {
    "use strict";

    /**
     * This file is only loaded for applications that don't use RequireJS
     * themselves, so we can initialize the common Master module immediately.
     */
    require(["cjt/startup"], function(STARTUP) {
        STARTUP.startMaster();
    });
});
