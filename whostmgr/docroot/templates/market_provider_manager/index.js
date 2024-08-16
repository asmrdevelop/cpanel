/*
# templates/ssl_provider_manager/index.js Copyright(c)             2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

/* global define: false, require: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute",
        "ngAnimate"
    ],
    function(angular, CJT) {

        "use strict";

        CJT.config.html5Mode = false;

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "ngAnimate"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/services/editProductsService",
                    "app/services/editCPStoreService",
                    "app/views/manageController",
                    "app/views/editProductsController",
                    "app/views/editCPStoreController",
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
                            $scope.onSelectTab = function(tabIndex) {
                                $scope.activeTabIndex = tabIndex;
                            };
                            $scope.go = function(path, tabIndex) {
                                $location.path(path);
                                $scope.active_path = path;
                                $scope.onSelectTab(tabIndex);
                            };

                            $scope.activeTabIndex = 0;
                        }
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup a route - copy this to add additional routes as necessary
                            $routeProvider.when("/", {
                                controller: "manageController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/manageView.ptt")
                            });

                            $routeProvider.when("/edit_products/", {
                                controller: "editProductsController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/editProducts.ptt")
                            });

                            $routeProvider.when("/edit_cpstore_config/", {
                                controller: "editCPStoreController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/editCPStore.ptt")
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/"
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
