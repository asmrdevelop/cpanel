/*
# templates/transfer_tool/restore_modules_summary.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngSanitize",
    ],
    function(angular) {
        "use strict";
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "ngSanitize",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/directives/toggleSortDirective",
                    "cjt/directives/searchDirective",
                    "app/controllers/RestoreModulesTableController",
                ], function(BOOTSTRAP) {

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
