/*
# templates/feature/manager.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/views/applicationController",
                    "cjt/filters/breakFilter",
                    "app/views/commonController",
                    "app/views/featureListController",
                    "app/views/editFeatureListController",
                    "cjt/services/whm/breadcrumbService"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        featureList: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/featureList", {
                                controller: "featureListController",
                                templateUrl: CJT.buildFullPath("feature/views/featureListView.ptt"),
                                breadcrumb: LOCALE.maketext("Feature Lists"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editFeatureList", {
                                controller: "editFeatureListController",
                                templateUrl: CJT.buildFullPath("feature/views/editFeatureListView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Feature List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: function(routeParams, path, search) {
                                    return "/featureList?" + window.location.search;
                                }
                            });
                        }
                    ]);

                    app.run(["breadcrumbService", function(breadcrumbService) {

                        // Setup the breadcrumbs service
                        breadcrumbService.initialize();
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
