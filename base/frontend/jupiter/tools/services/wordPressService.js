/*
# cpanel - base/frontend/jupiter/tools/services/wordPressService.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/uapi-request",
        "cjt/io/uapi", // IMPORTANT: Load the driver so its ready
        "cjt/services/APICatcher",
    ],
    function(angular, API, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("cpanel.tools.service.wordPressService", []);

        /**
         * Setup the WordPress polling service.
         */
        app.factory("wordPressService", ["$q", "APICatcher",
            function($q, apiCatcher) {

                // return the factory interface
                return {
                    startPolling: function() {
                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("WordPressSite", "retrieve", {});
                        return apiCatcher.promise(apiCall);
                    },
                };
            },
        ]);
    }
);
