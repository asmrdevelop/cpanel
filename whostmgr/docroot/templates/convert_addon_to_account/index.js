/*
# index.js                                        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "uiBootstrap"
    ],
    function(angular, $, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ngAnimate",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/services/pageDataService",
                    "app/services/ConvertAddonData",
                    "app/services/Databases",
                    "app/services/account_packages",
                    "app/services/conversion_history",
                    "app/filters/local_datetime_filter",
                    "app/views/main",
                    "app/views/move_options",
                    "app/views/docroot",
                    "app/views/dns",
                    "app/views/email_options",
                    "app/views/db_options",
                    "app/views/conversion_detail",
                    "app/views/subaccounts",
                    "app/views/history",
                    "app/directives/move_status",
                    "app/directives/job_status"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.firstLoad = {
                        addonList: true
                    };

                    // setup the defaults for the various services.
                    app.factory("defaultInfo", [
                        "pageDataService",
                        function(pageDataService) {
                            return pageDataService.prepareDefaultInfo(PAGE);
                        }
                    ]);

                    app.config([
                        "$routeProvider",
                        "$anchorScrollProvider",
                        function($routeProvider,
                            $anchorScrollProvider) {

                            $anchorScrollProvider.disableAutoScrolling();

                            // Setup the routes
                            $routeProvider.when("/main", {
                                controller: "mainController",
                                controllerAs: "main",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/main.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations", {
                                controller: "moveSelectionController",
                                controllerAs: "move_options_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/move_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/docroot", {
                                controller: "docrootController",
                                controllerAs: "docroot",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/docroot.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/email", {
                                controller: "emailSelectionController",
                                controllerAs: "email_selection_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/email_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/databases", {
                                controller: "databaseSelectionController",
                                controllerAs: "db_selection_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/db_options.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/dns", {
                                controller: "dnsSelectionController",
                                controllerAs: "dns",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/dns.ptt")
                            });

                            $routeProvider.when("/convert/:addondomain/migrations/edit/subaccounts", {
                                controller: "subaccountSelectionController",
                                controllerAs: "sub_vm",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/subaccounts.ptt")
                            });

                            $routeProvider.when("/history", {
                                controller: "historyController",
                                controllerAs: "history",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/history.ptt")
                            });

                            $routeProvider.when("/history/:jobid/detail", {
                                controller: "conversionDetailController",
                                controllerAs: "detail",
                                templateUrl: CJT.buildFullPath("convert_addon_to_account/views/conversion_detail.ptt"),
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/main"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$anchorScroll", "$timeout", "$location", "growl", "growlMessages",
                        function($rootScope, $anchorScroll, $timeout, $location, growl, growlMessages) {

                            // account for the extra margin from the pageContainer div
                            $anchorScroll.yOffset = 41;
                        }
                    ]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
