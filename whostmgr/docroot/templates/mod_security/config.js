/*
# templates/mod_security/config.js                Copyright(c) 2020 cPanel, L.L.C.
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
                "app/views/commonController",
                "app/views/configController",
                "cjt/services/autoTopService",
                "cjt/services/whm/breadcrumbService",
                "cjt/services/whm/titleService"
            ], function(BOOTSTRAP, LOCALE) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.firstLoad = {
                    configs: true,
                    vendors: true
                };

                // routing
                app.config(["$routeProvider",
                    function($routeProvider) {

                        // Configuration
                        $routeProvider.when("/config", {
                            controller: "configController",
                            templateUrl: CJT.buildFullPath("mod_security/views/configView.ptt"),
                            breadcrumb: LOCALE.maketext("Configure Global Directives"),
                            title: LOCALE.maketext("Configure Global Directives"),
                            reloadOnSearch: false,
                            group: "config",
                            name: "config"
                        });

                        $routeProvider.otherwise({
                            redirectTo: function(routeParams, path, search) {
                                return "/config?" + window.location.search;
                            }
                        });
                    }
                ]);

                app.run(["autoTopService", "breadcrumbService", "titleService", function(autoTopService, breadcrumbService, titleService) {

                    // Setup the automatic scroll to top for view changes
                    autoTopService.initialize();

                    // Setup the breadcrumbs service
                    breadcrumbService.initialize();

                    // Setup the title update service
                    titleService.initialize();
                }]);

                BOOTSTRAP(document);

            });

        return app;
    }
);
