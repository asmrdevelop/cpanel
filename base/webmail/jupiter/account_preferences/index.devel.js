/*
# cpanel - base/webmail/jupiter/account_preferences/index.devel.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/*
# account_preferences/index.devel.js               Copyright 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the non-combined files
require(
    [
        "master/master",
        "app/index",
    ],
    function(MASTER, APP) {

        "use strict";

        MASTER();
        APP();
    }
);
