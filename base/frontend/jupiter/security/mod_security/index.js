/*
# security/mod_security/index.js                  Copyright(c) 2020 cPanel, L.L.C.
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
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", ["ngRoute", "ui.bootstrap", "cjt2.cpanel"]);

            // Then load the application dependencies
            var app = require(
                [

                    // Application Modules
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/views/domainListController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.firstLoad = {
                        domainList: true,
                    };

                    // routing
                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/domainList/", {
                                controller: "domainListController",
                                templateUrl: CJT.buildFullPath("security/mod_security/views/domainListView.ptt")
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/domainList/"
                            });
                        }
                    ]);

                    BOOTSTRAP("#content", "App");

                });

            return app;
        };
    }
);
