/*
# mail/search_index/index.dist.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false */

require([
    "frameworksBuild",
    "locale!cjtBuild",
    "locale!app/index.cmb"
],
function() {
    require(
        [
            "app/index"
        ],
        function(APP) {
            "use strict";
            APP();
        }
    );
});
