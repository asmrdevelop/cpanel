/**
 * base/unprotected/invitation.dist.js                Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global require: false */

// Loads the application with the pre-built combined files
require([
    "frameworksBuild",
    "locale!cjtBuild",
    "app/invitation.cmb"
],
function() {
    "use strict";

    require(
        [
            "app/invitation"
        ],
        function(INVITATION) {
            INVITATION();
        }
    );
}
);
