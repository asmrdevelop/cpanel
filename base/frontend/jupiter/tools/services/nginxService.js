/*
# cpanel - base/frontend/jupiter/tools/services/nginxService.js
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
    function(angular, API, APIREQUEST, APIDRIVER) {
        "use strict";

        // Fetch the current application
        var app = angular.module("cpanel.tools.service.nginxService", []);

        /**
         * Setup the account list model's API service
         */
        app.factory("nginxService", ["$q", "APICatcher",
            function($q, apiCatcher) {

                // return the factory interface
                return {

                    /**
                     * Clear NGINX caching for the cPanel user.
                     * @return {Promise} - Promise that will fulfill the request.
                     */
                    clearCache: function() {
                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("NginxCaching", "clear_cache", {});
                        return apiCatcher.promise(apiCall);
                    },

                    /**
                     * Enable NGINX caching for the cPanel user.
                     * @return {Promise} - Promise that will fulfill the request.
                     */
                    enableCaching: function() {
                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("NginxCaching", "enable_cache", {});
                        return apiCatcher.promise(apiCall);
                    },

                    /**
                     * Disable NGINX caching for the cPanel user.
                     * @return {Promise} - Promise that will fulfill the request.
                     */
                    disableCaching: function() {
                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("NginxCaching", "disable_cache", {});
                        return apiCatcher.promise(apiCall);
                    },
                };
            },
        ]);
    }
);
