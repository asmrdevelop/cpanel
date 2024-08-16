/*
# whostmgr/docroot/templates/file_and_directory_restoration/index.js
#                                                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require: false, define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, CJT) {
        "use strict";
        return function() {
            angular.module("whm.fileAndDirectoryRestore", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/views/backup_restore",
                    "app/filters/file_size_filter"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.fileAndDirectoryRestore");

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {
                            $routeProvider.when("/backup_restore", {
                                controller: "listController",
                                templateUrl: "file_and_directory_restoration/views/backup_restore.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/backup_restore"
                            });
                        }
                    ]);

                    BOOTSTRAP(document, "whm.fileAndDirectoryRestore");

                });

            return app;
        };
    }
);
