/*
# twofactorauth/index.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    [
        "angular",
        "jquery",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/services/tfaData",
                    "angular-growl",
                    "app/views/disablePromptController",
                    "app/views/usersController",
                    "app/views/enableController",
                    "app/views/configController",
                    "app/views/setupController"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    // routing
                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/config", {
                                controller: "configController",
                                controllerAs: "cc",
                                templateUrl: CJT.buildFullPath("twofactorauth/views/configView.ptt"),
                            });

                            $routeProvider.when("/users", {
                                controller: "usersController",
                                controllerAs: "uc",
                                templateUrl: CJT.buildFullPath("twofactorauth/views/usersView.ptt"),
                            });

                            $routeProvider.when("/myaccount", {
                                controller: "setupController",
                                controllerAs: "setup",
                                templateUrl: CJT.buildFullPath("twofactorauth/views/setupView.ptt"),
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/config"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "TwoFactorData", "growl", "growlMessages",
                        function($rootScope, $timeout, $location, TwoFactorData, growl, growlMessages) {

                            // register listener to watch route changes
                            $rootScope.$on("$routeChangeStart", function() {
                                $rootScope.currentRoute = $location.path();
                            });
                        }]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);
