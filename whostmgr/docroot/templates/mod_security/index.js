/*
# templates/mod_security/index.js                 Copyright(c) 2020 cPanel, L.L.C.
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
                    "app/views/hitListController",
                    "app/views/rulesListController",
                    "app/views/addRuleController",
                    "app/views/editRuleController",
                    "app/views/massEditRuleController",
                    "app/views/reportController",
                    "cjt/services/autoTopService",
                    "cjt/services/whm/breadcrumbService"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        hitList: true,
                        rules: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/hitList", {
                                controller: "hitListController",
                                templateUrl: CJT.buildFullPath("mod_security/views/hitListView.ptt"),
                                breadcrumb: LOCALE.maketext("Hits List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/rulesList", {
                                controller: "rulesListController",
                                templateUrl: CJT.buildFullPath("mod_security/views/rulesListView.ptt"),
                                breadcrumb: LOCALE.maketext("Rules List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/addCustomRule", {
                                controller: "addRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Add Custom Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/copyCustomRule", {
                                controller: "addRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Copy Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editCustomRule", {
                                controller: "editRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/addEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Custom Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editCustomRules", {
                                controller: "massEditRuleController",
                                templateUrl: CJT.buildFullPath("mod_security/views/massEditRuleView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Custom Rules"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/report/hit/:hitId", {
                                controller: "reportController",
                                templateUrl: CJT.buildFullPath("mod_security/views/reportView.ptt"),
                                breadcrumb: LOCALE.maketext("Report ModSecurity Hit"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/report/:vendorId/rule/:ruleId", {
                                controller: "reportController",
                                templateUrl: CJT.buildFullPath("mod_security/views/reportView.ptt"),
                                breadcrumb: LOCALE.maketext("Report ModSecurity Rule"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: function(routeParams, path, search) {
                                    return "/hitList?" + window.location.search;
                                }
                            });
                        }
                    ]);

                    app.run(["autoTopService", "breadcrumbService", function(autoTopService, breadcrumbService) {

                        // Setup the automatic scroll to top for view changes
                        autoTopService.initialize();

                        // Setup the breadcrumbs service
                        breadcrumbService.initialize();
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
