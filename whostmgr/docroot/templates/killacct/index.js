/* global define, require, PAGE */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute"
    ],
    function(angular, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
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
                    "app/views/RemoveController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    app.config(["growlProvider", "$httpProvider",
                        function(growlProvider, $httpProvider) {
                            growlProvider.globalReversedOrder(true);
                            growlProvider.globalTimeToLive({ success: -1, warning: -1, info: -1, error: -1 });
                            $httpProvider.useApplyAsync(true);
                        }
                    ]);


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
                            $routeProvider.when("/:user?", {
                                controller: "RemoveController",
                                templateUrl: CJT.buildFullPath("killacct/views/RemoveView.ptt"),
                                resolve: {}
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/"
                            });

                        }
                    ]);

                    // end of using views

                    // Initialize the application
                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
