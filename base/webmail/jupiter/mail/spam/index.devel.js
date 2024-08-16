/*
# cpanel - base/webmail/jupiter/mail/spam/index.devel.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require(
    [
        "master/master",
        "app/index",
    ],
    function(MASTER, APP) {
        MASTER();
        APP();
    }
);
