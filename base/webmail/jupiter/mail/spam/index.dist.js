/*
# cpanel - base/webmail/jupiter/mail/spam/index.dist.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W098 */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "app/index.cmb",
    "master/master.cmb",
], function() {
    require(["cjt/startup"], function(STARTUP) {
        STARTUP
            .startApplication()
            .deferStartMaster();
    });
});
