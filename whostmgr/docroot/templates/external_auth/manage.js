/*
# templates/external_auth/manage                       Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "cjt/modules",
    ],
    function(angular, _, CJT, LOCALE) {
        "use strict";

        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load first
            "ui.bootstrap",
            "cjt2.whm",
            "angular-growl"
        ]);

        var app = require(
            [
                "cjt/bootstrap",

                // Application Modules
                "uiBootstrap",
                "app/services/UsersService",
                "app/services/ProvidersService",
                "app/views/UsersController",
                "app/views/ManageUserController",
                "app/views/ProvidersController",
                "app/views/ConfigureProviderController",
                "cjt/decorators/growlDecorator",
            ],
            function(BOOTSTRAP) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location",
                    function($rootScope, $scope, $route, $location) {

                        $scope.loading = false;
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

                app.config(["$routeProvider",
                    function($routeProvider) {

                        function _fetch_providers(ProvidersService, growl) {
                            return ProvidersService.fetch_providers().then(function() {

                                // providers loaded
                            }, function(error) {
                                growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the providers: [_1]", error));
                            });
                        }

                        function _fetch_users(UsersService, ProvidersService, growl) {
                            return UsersService.fetch_users().then(function() {

                                // users loaded
                                return ProvidersService.fetch_providers().then(function() {

                                    // providers Loaded
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the providers: [_1]", error));
                                });
                            }, function(error) {
                                growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the users: [_1]", error));
                            });
                        }

                        // Setup the routes
                        $routeProvider.when("/providers", {
                            controller: "ProvidersController",
                            templateUrl: CJT.buildFullPath("external_auth/views/providers.ptt"),
                            resolve: {
                                providers: ["ProvidersService", "growl", _fetch_providers]
                            }
                        });

                        $routeProvider.when("/providers/:providerID", {
                            controller: "ConfigureProviderController",
                            templateUrl: CJT.buildFullPath("external_auth/views/configure_provider.ptt"),
                            resolve: {
                                providers: ["ProvidersService", "growl", _fetch_providers]
                            }
                        });

                        // Setup the routes
                        $routeProvider.when("/users", {
                            controller: "UsersController",
                            templateUrl: CJT.buildFullPath("external_auth/views/users.ptt"),
                            resolve: {
                                providers: ["UsersService", "ProvidersService", "growl", _fetch_users]
                            }
                        });

                        $routeProvider.when("/users/:userID", {
                            controller: "ManageUserController",
                            templateUrl: CJT.buildFullPath("external_auth/views/manage_user.ptt"),
                            resolve: {
                                providers: ["UsersService", "ProvidersService", "growl", _fetch_users]
                            }
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/users"
                        });

                    }
                ]);

                BOOTSTRAP(document);
            });

        return app;
    }
);
