/*
# templates/greylist/index.js                          Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */
/* jshint -W100 */

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
        "ngAnimate"
    ],
    function(angular, $, _, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/services/GreylistDataSource",
                    "app/filters/ipWrapFilter",
                    "app/views/base",
                    "app/views/config",
                    "app/views/trustedHosts",
                    "app/views/reports",
                    "app/views/mailServices"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "configController",
                                templateUrl: CJT.buildFullPath("greylist/views/config.ptt"),
                            });

                            $routeProvider.when("/trusted", {
                                controller: "trustedHostsController",
                                templateUrl: CJT.buildFullPath("greylist/views/trustedHosts.ptt"),
                            });

                            $routeProvider.when("/reports", {
                                controller: "reportsController",
                                templateUrl: CJT.buildFullPath("greylist/views/reports.ptt"),
                            });

                            $routeProvider.when("/commonproviders", {
                                controller: "mailServices",
                                templateUrl: CJT.buildFullPath("greylist/views/mailServices.ptt"),
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/config"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "GreylistDataSource", "growl", "growlMessages", function($rootScope, $timeout, $location, GreylistDataSource, growl, growlMessages) {

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
