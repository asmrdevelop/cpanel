/*
# templates/tls_wizard_redirect/index.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */


define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute"
    ],
    function(angular, CJT) {

        CJT.config.html5Mode = false;

        return function() {

            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/indexService",
                    "app/views/purchaseRedirectController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    // If using views
                    app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location",
                        function($rootScope, $scope, $route, $location) {

                            $scope.loading = false;

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function() {
                                $scope.loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                $scope.loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function() {
                                $scope.loading = false;
                            });
                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };
                            $scope.go = function(path) {
                                $location.path(path);
                            };
                        }
                    ]);

                    // viewName

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup a route - copy this to add additional routes as necessary
                            $routeProvider.when("/purchaseRedirect", {
                                controller: "purchaseRedirectController",
                                templateUrl: CJT.buildFullPath("tls_wizard_redirect/views/purchaseRedirectView.ptt"),
                                resolve: {}
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/purchaseRedirect"
                            });

                        }
                    ]);

                    // end of using views

                    BOOTSTRAP();

                });

            return app;
        };
    }
);
