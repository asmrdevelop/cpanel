/*
# cpanel - whostmgr/docroot/templates/configure_cpanel_analytics/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-env amd */

define(
    [
        "angular",
        "cjt/util/parse",
        "cjt/modules",
        "ngRoute",
        "ngSanitize",
        "uiBootstrap",
    ],
    function(angular, PARSE) {

        "use strict";

        return function() {

            require(
                [
                    "cjt/bootstrap",
                    "cjt/directives/alertList",
                    "app/views/mainController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.configureAnalytics", [
                        "cjt2.config.whm.configProvider", // This needs to load before ngRoute
                        "ngRoute",
                        "ui.bootstrap",
                        "cjt2.directives.alertList",
                        "whm.configureAnalytics.mainController",
                    ]);

                    app.config([
                        "$routeProvider", "$locationProvider",
                        function($routeProvider, $locationProvider) {

                            $routeProvider.when("/main", {
                                controller: "mainController",
                                controllerAs: "vm",
                                templateUrl: "configure_cpanel_analytics/views/mainView.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/main",
                            });
                        },
                    ]);

                    app.value("PAGE", window.PAGE);

                    BOOTSTRAP("#content", "whm.configureAnalytics");

                });
        };
    }
);
