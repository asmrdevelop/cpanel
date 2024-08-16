/*
# templates/transfer_tool/restore_modules_summary.devel.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

// Loads the application with the non-combined files
require(
    [
        "app/restore_modules_summary"
    ],
    function(APP) {
        "use strict";
        APP();
    }
);
