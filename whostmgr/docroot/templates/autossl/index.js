/*
# whostmgr/docroot/templates/autossl/index.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */
/* eslint-disable camelcase */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "cjt/modules",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "app/directives/starRating",
    ],
    function(_, angular, LOCALE, CJT) {
        "use strict";

        CJT.config.html5Mode = false;

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whostmgr.autossl.starRating",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/views/select_provider_controller",
                    "app/views/view_logs_controller",
                    "app/services/AutoSSLConfigureService",
                    "app/views/ManageUsersController",
                    "app/views/OptionsController",
                ],
                function(BOOTSTRAP) {

                    var tab_configs = [{
                        path: "/providers/",
                        label: LOCALE.maketext("Providers"),
                        controller: "select_provider_controller",
                        templateUrl: CJT.buildFullPath("autossl/views/select_provider.ptt"),
                    }, {
                        path: "/options/",
                        label: LOCALE.maketext("Options"),
                        controller: "OptionsController",
                        templateUrl: CJT.buildFullPath("autossl/views/options.ptt"),
                    }, {
                        path: "/view-logs/",
                        label: LOCALE.maketext("Logs"),
                        controller: "view_logs_controller",
                        templateUrl: CJT.buildFullPath("autossl/views/view_logs.ptt"),
                    }, {
                        path: "/manage-users/",
                        label: LOCALE.maketext("Manage Users"),
                        controller: "ManageUsersController",
                        templateUrl: CJT.buildFullPath("autossl/views/manage-users.ptt"),
                        resolve: {
                            "ssl_users": ["AutoSSLConfigureService",
                                function(service) {
                                    return service.fetch_users();
                                },
                            ],
                        },
                    }];
                    var default_tab = tab_configs[0].path;

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "$route",
                        "$location",
                        "manageService",
                        "AutoSSLConfigureService",
                        "growl",
                        function($rootScope, $scope, $route, $location, manageService, AutoSSLConfigureService, growl) {
                            $scope.loading = false;
                            $scope.activeTabs = [];

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function(eo, next) {
                                $scope.onLoadTab(next.path);
                                $scope.active_path = next.path;
                                $scope.loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                $scope.loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function() {
                                $scope.loading = false;
                                $scope.go("providers");
                            });

                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };

                            $scope.onLoadTab = function(loaded_path) {
                                $scope.activeTabs.forEach(function(value, key) {
                                    if (value.path === loaded_path) {
                                        $scope.currentTab = key;
                                    }
                                });
                            };

                            $scope.updated_current_module = function() {
                                $scope.current_provider_module = manageService.get_saved_provider_module_name();
                            };

                            $scope.$on("provider-module-updated", function() {
                                $scope.updated_current_module();
                            });

                            $scope.go = function(path) {
                                $location.path(path);
                            };

                            function init() {
                                $scope.activeTabs = tab_configs;
                                $scope.updated_current_module();
                            }

                            init();

                            // ----------------------------------------------------------------------
                            // Should the following be in its own view?
                            function _growl_error(result) {
                                return growl.error(_.escape(result.error));
                            }

                            angular.extend($scope, {
                                next_check_time_string: function() {
                                    var time = manageService.get_next_autossl_check_time();
                                    if (time) {

                                        // datetime() always kicks out UTC.
                                        // We could use local_datetime(), but
                                        // that would break compatibility with
                                        // Perl’s Locale, which doesn’t have
                                        // local_datetime(). So, instead we
                                        // “trick” datetime() by feeding it
                                        // an offset epoch seconds count.
                                        var compensated_time = time;
                                        compensated_time -= 60 * 1000 * time.getTimezoneOffset();
                                        compensated_time /= 1000;

                                        return LOCALE.maketext("This system’s next regular [asis,AutoSSL] check will occur at [datetime,_1,time_format_short].", Math.round(compensated_time));
                                    }
                                },

                                getSavedProviderAccountID: manageService.getSavedProviderAccountID.bind(manageService),

                                getCurrentProviderDisplayName: function() {
                                    return manageService.get_provider_display_name(manageService.get_saved_provider_module_name());
                                },

                                get_saved_provider_module_name: manageService.get_saved_provider_module_name,

                                start_autossl_for_all_users: function() {
                                    return manageService.start_autossl_for_all_users().then(
                                        function(result) {
                                            growl.success(LOCALE.maketext("[asis,AutoSSL] is now checking all users. The process has [asis,ID] “[_1]”.", result.data.pid));
                                        },
                                        _growl_error
                                    );
                                },
                            });
                        },
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            tab_configs.forEach(function(tab) {
                                $routeProvider.when(tab.path, tab);
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": default_tab,
                            });
                        },
                    ]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);
