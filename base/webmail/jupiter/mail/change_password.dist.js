/*
# cpanel - base/webmail/jupiter/mail/change_password.dist.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require(["frameworksBuild", "locale!cjtBuild", "app/change_password.cmb"], function() {
    require(
        [
            "master/master",
            "app/change_password",
        ],
        function(MASTER, APP) {
            MASTER();
            APP();
        }
    );
});
