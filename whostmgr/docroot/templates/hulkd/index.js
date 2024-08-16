/*
# cpanel - whostmgr/docroot/templates/hulkd/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* eslint-disable camelcase */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
        "ngAnimate",
    ],
    function(angular, $, _, LOCALE, CJT) {
        "use strict";
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm",
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/configController",
                    "app/views/countriesController",
                    "app/views/hulkdWhitelistController",
                    "app/views/hulkdBlacklistController",
                    "app/views/historyController",
                    "app/views/hulkdEnableController",
                    "app/services/HulkdDataSource",
                    "angular-growl",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);
                    app.value("COUNTRY_CONSTANTS", {
                        WHITELISTED: "whitelisted",
                        BLACKLISTED: "blacklisted",
                        UNLISTED: "unlisted",
                    });

                    // used to indicate that we are prefetching the following items
                    app.firstLoad = {
                        configs: true,
                    };

                    app.controller("BaseController", ["$rootScope", "$scope",
                        function($rootScope, $scope) {

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
                        },
                    ]);

                    app.config(["$routeProvider", "$animateProvider",
                        function($routeProvider, $animateProvider) {

                            $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "configController",
                                templateUrl: CJT.buildFullPath("hulkd/views/configView.ptt"),
                            });

                            $routeProvider.when("/whitelist", {
                                controller: "hulkdWhitelistController",
                                templateUrl: CJT.buildFullPath("hulkd/views/hulkdWhitelistView.ptt"),
                            });

                            $routeProvider.when("/blacklist", {
                                controller: "hulkdBlacklistController",
                                templateUrl: CJT.buildFullPath("hulkd/views/hulkdBlacklistView.ptt"),
                            });

                            $routeProvider.when("/history", {
                                controller: "historyController",
                                templateUrl: CJT.buildFullPath("hulkd/views/historyView.ptt"),
                            });

                            $routeProvider.when("/countries", {
                                controller: "countriesController",
                                templateUrl: CJT.buildFullPath("hulkd/views/countriesView.ptt"),
                                resolve: {
                                    "COUNTRY_CODES": ["HulkdDataSource", function($service) {
                                        return $service.get_countries_with_known_ip_ranges();
                                    }],
                                    "XLISTED_COUNTRIES": ["HulkdDataSource", function($service) {
                                        return $service.load_xlisted_countries();
                                    }],
                                },
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/config",
                            });
                        },
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "HulkdDataSource", "growl", "growlMessages", function($rootScope, $timeout, $location, HulkdDataSource, growl, growlMessages) {

                        // register listener to watch route changes
                        $rootScope.$on( "$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });

                        $rootScope.whitelist_warning_message = null;
                        $rootScope.ip_added_with_one_click = false;

                        $rootScope.one_click_add_to_whitelist = function(missing_ip) {
                            return HulkdDataSource.add_to_whitelist([{ ip: missing_ip } ])
                                .then(function(results) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the whitelist.", results.added[0]));

                                    // check if the client ip is in the whitelist and if our growl is still shown, remove it
                                    if ((Object.prototype.hasOwnProperty.call(results, "requester_ip") &&
                                         results.added.indexOf(results.requester_ip) > -1) &&
                                         ($rootScope.whitelist_warning_message !== null)) {

                                        // remove is handled in this manner because it was not removing the growl in the right sequence
                                        // when shown with other growls
                                        $rootScope.whitelist_warning_message.ttl = 0;
                                        $rootScope.whitelist_warning_message.promises = [];
                                        $rootScope.whitelist_warning_message.promises.push($timeout(angular.bind(growlMessages, function() {
                                            growlMessages.deleteMessage($rootScope.whitelist_warning_message);
                                            $rootScope.whitelist_warning_message = null;
                                        }), 200));
                                        $rootScope.ip_added_with_one_click = true;
                                    }
                                }, function(error_details) {
                                    var combined_message = error_details.main_message;
                                    var secondary_count = error_details.secondary_messages.length;
                                    for (var z = 0; z < secondary_count; z++) {
                                        if (z === 0) {
                                            combined_message += "<br>";
                                        }
                                        combined_message += "<br>";
                                        combined_message += error_details.secondary_messages[z];
                                    }
                                    growl.error(combined_message);
                                });
                        };
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
