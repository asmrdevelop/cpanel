/*
# cpanel - base/webmail/jupiter/account_preferences/index.dist.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "locale!app/index.cmb",
],
function() {

    "use strict";

    require(
        [
            "app/index",
        ],
        function(APP) {
            APP();
        }
    );


    // Defer this since the primary task here is this page,
    // so we can wait a sec for the search tool to start working...
    setTimeout(function() {
        require(
            [
                "master/master",
            ],
            function(MASTER) {
                MASTER();
            }
        );
    }, 5);
});
