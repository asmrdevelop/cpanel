/*
# templates/mailbox_converter/index.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute",
        "ngAnimate",
    ],
    function(angular, CJT, LOCALE) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "ngAnimate"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "cjt/services/whm/breadcrumbService",
                    "app/services/indexService",
                    "app/views/selectAccountsController",
                    "app/views/selectFormatController",
                    "app/views/confirmController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    var steps = [
                        {
                            route: "select_format",
                            breadcrumb: LOCALE.maketext("Select Format"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/selectFormatView.ptt"),
                            controller: "selectFormatController",
                            default: true,
                            is_ready: function requires($q) {
                                return $q(function(resolve) {
                                    resolve("");
                                });
                            }
                        },
                        {
                            route: "select_accounts",
                            breadcrumb: LOCALE.maketext("Select Accounts"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/selectAccountsView.ptt"),
                            controller: "selectAccountsController",
                            is_ready: function requires($q, service) {
                                return $q(function(resolve, reject) {
                                    if (!!service.get_format()) {
                                        resolve("");
                                    } else {
                                        reject("Missing necessary data");
                                    }
                                });
                            }
                        },
                        {
                            route: "finalize",
                            breadcrumb: LOCALE.maketext("Review and Finalize"),
                            templateUrl: CJT.buildFullPath("mailbox_converter/views/confirmView.ptt"),
                            controller: "confirmController",
                            is_ready: function requires($q, service) {
                                var _accounts = service.get_accounts();
                                var has_selected_account = false;
                                if (_accounts) {
                                    for (var x = 0; x < _accounts.length; x++) {
                                        if (_accounts[x].selected) {
                                            has_selected_account = true;
                                            break;
                                        }
                                    }
                                }
                                return $q(function(resolve, reject) {

                                    if (!!service.get_format() && has_selected_account) {
                                        resolve("");
                                    } else {
                                        reject("Missing necessary data");
                                    }
                                });
                            }
                        }
                    ];

                    // If using views
                    app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location", "indexService", "$q", "PAGE", "$window",
                        function($rootScope, $scope, $route, $location, indexService, $q, PAGE, $window) {

                            $scope.steps = steps;
                            $scope.current_step = 0;
                            $scope.LOCALE = LOCALE;
                            var _loading = false;


                            indexService.set_accounts(PAGE.data.accounts);

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function(event, currentRoute, previousRoute) {

                                // If the user hits the back button we want to verify that we adjust the current_page
                                //  so the UI updates appropriately
                                if (previousRoute && typeof previousRoute.$$route !== "undefined" && previousRoute.$$route.page === $scope.current_step) {
                                    $scope.current_step = currentRoute.$$route.page;
                                }
                                _loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                _loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function(event, currentRoute, previousRoute) {
                                _loading = false;

                                // Handles the case where user uses forward button to get onto bad route
                                if (previousRoute) {
                                    $location.path(steps[previousRoute.$$route.page].route).replace();
                                    return;
                                }

                                // handles the case when user manually goes to bad route
                                $location.path(steps[$scope.current_step].route).replace();
                            });
                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };

                            $scope.get_view_styles = function() {
                                var _view_classes = [];
                                if (_loading) {
                                    _view_classes.push("view-disabled");
                                }
                                return _view_classes;
                            };

                            $scope.submit_form = function(form_id) {
                                document.getElementById(form_id).submit();
                            };

                            $scope.go_back = function(index, current_step) {
                                if (typeof index === "undefined") {
                                    $window.history.back();
                                    $scope.current_step = $scope.current_step - 1;
                                    return;
                                } else {
                                    var loop_counter = current_step - index;
                                    while (loop_counter > 0) {
                                        $window.history.back();
                                        loop_counter--;
                                    }
                                    $scope.current_step = index;
                                }
                            };

                            $scope.go = function(index, isValid) {
                                if (!isValid) {
                                    return;
                                }
                                steps[index].is_ready($q, indexService).then(function() {
                                    $location.path(steps[index].route);
                                    $scope.current_step = index;
                                }, function() {

                                    // don't do anything in the case they aren't allowed to go forward
                                });
                            };
                        }
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {
                            var page_number = 0;
                            steps.forEach(function(step) {
                                $routeProvider.when("/" + step.route, {
                                    controller: step.controller,
                                    templateUrl: step.templateUrl,
                                    breadcrumb: step.breadcrumb,
                                    resolve: {
                                        data: ["$q", "indexService", step.is_ready] // this is called twice on page change -- could be optimized
                                    },
                                    page: page_number++
                                });

                                if (step.hasOwnProperty("default") && step.default) {
                                    $routeProvider.otherwise({
                                        "redirectTo": "/" + step.route
                                    });
                                }
                            });
                        }
                    ]);

                    app.run([
                        "breadcrumbService",
                        function(breadcrumbService) {
                            breadcrumbService.initialize();
                        }
                    ]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);
