/*
# templates/yumupdate/index.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",

        // "cjt/validator/validateDirectiveFactory",
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/views/applicationController",
                    "app/views/landing",
                    "app/services/yumAPI"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/landing", {
                                controller: "landing",
                                templateUrl: CJT.buildFullPath("yumupdate/views/landing.ptt")
                            })
                                .otherwise({
                                    "redirectTo": "/landing"
                                });
                        }
                    ]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
