/*
# templates/cpanel_plugin_manager/index.js                 Copyright 2022 cPanel, L.L.C.
#                                                          All rights reserved.
# copyright@cpanel.net                                     http://cpanel.net
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
        "ngRoute"
    ],
    function(angular, $, _, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/views/applicationController",
                    "app/views/createPluginController",
                    "app/directives/fileModel",
                    "app/directives/fileType",
                    "cjt/directives/autoFocus",
                    "cjt/services/autoTopService",
                    "cjt/directives/actionButtonDirective"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        pluginList: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/createPlugin", {
                                controller: "createPluginController",
                                templateUrl: CJT.buildFullPath("cpanel_plugin_manager/views/createPluginView.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: "/createPlugin"
                            });
                        }
                    ]);

                    app.run(["autoTopService", function(autoTopService) {

                        // Setup the automatic scroll to top for view changes
                        autoTopService.initialize();
                    }]);

                    // Initialize the application
                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
