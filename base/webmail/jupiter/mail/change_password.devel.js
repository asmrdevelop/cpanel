/*
# cpanel - base/webmail/jupiter/mail/change_password.devel.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the non-combined files
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
