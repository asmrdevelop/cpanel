/*
# backup_configuration/index.js                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "app/services/backupConfigurationServices",
        "app/services/validationLog"
    ],
    function(angular, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.backupConfiguration", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "cjt2.whm",
                "whm.backupConfiguration.backupConfigurationServices.service",
                "whm.backupConfiguration.validationLog.service"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/directives/formValidator",
                    "app/views/config",
                    "app/views/destinations",
                    "app/views/validationResults"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.backupConfiguration");
                    app.value("PAGE", PAGE);

                    app.controller("BaseController", ["$rootScope", "$scope", "$location",
                        function($rootScope, $scope, $location) {

                            $scope.loading = false;
                            $rootScope.$on("$routeChangeStart", function() {
                                $scope.loading = true;
                                $rootScope.currentRoute = $location.path();
                            });
                        }
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/settings", {
                                controller: "config",
                                templateUrl: "views/config.ptt"
                            });

                            $routeProvider.when("/destinations", {
                                controller: "destinations",
                                templateUrl: "views/destinations.ptt"
                            });

                            $routeProvider.when("/validation", {
                                controller: "validationResults",
                                templateUrl: "views/validationResults.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/settings"
                            });
                        }
                    ]);

                    var appContent = angular.element("#pageContainer");
                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        BOOTSTRAP(appContent[0], "whm.backupConfiguration");
                    }

                });

            return app;
        };
    }
);
