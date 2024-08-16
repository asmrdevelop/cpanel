/*
# whostmgr/docroot/templates/license_purchase/index.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, require:false */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/core",
        "cjt/util/parse",
        "cjt/modules",
        "shared/js/license_purchase/services/storeService",
    ],
    function(_, angular, CJT) {
        "use strict";

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "angular-growl",
                "ngRoute",
                "cjt2.whm",
                "whm.storeService",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/decorators/growlDecorator",
                    "app/views/checkoutController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "$route",
                        "$location",
                        function($rootScope, $scope) {
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
                        }
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup a route - copy this to add additional routes as necessary
                            $routeProvider.when("/checkout/:nextStep?/:everythingelse?", {
                                controller: "checkoutController",
                                templateUrl: CJT.buildFullPath("license_purchase/views/checkout.ptt")
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/checkout/"
                            });
                        }
                    ]);

                    // Initialize the application
                    BOOTSTRAP();

                });

            return app;
        };
    }
);
