/*
# templates/backup_migration/index.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("whm.backupMigration", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/views/applicationController",
                    "app/views/main",
                    "app/services/backupMigrationAPI"
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.backupMigration");

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/main", {
                                controller: "main",
                                templateUrl: CJT.buildFullPath("backup_migration/views/main.ptt")
                            })
                                .otherwise({
                                    "redirectTo": "/main"
                                });
                        }
                    ]);

                    BOOTSTRAP(document, "whm.backupMigration");

                });

            return app;
        };
    }
);
