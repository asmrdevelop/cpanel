/**
 * base/unprotected/resetpass.js                      Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global require: false, define: false */

define([
    "angular",
    "cjt/core",
    "cjt/modules",
    "uiBootstrap"
],
function(angular, CJT) {
    "use strict";

    return function() {

        // First create the application
        angular.module("App", [
            "ngRoute",
            "ui.bootstrap",
            "cjt2.unprotected"
        ]);

        // Then load the application dependencies
        var app = require([

            // Application Modules
            "cjt/views/applicationController",
            "cjt/services/autoTopService",
            "app/controllers/puzzleController",
            "app/controllers/setPasswordController",
        ], function() {

            var app = angular.module("App");

            // routing
            app.config([
                "$compileProvider",
                function(
                    $compileProvider
                ) {

                    if (!CJT.config.debug) {
                        $compileProvider.debugInfoEnabled(false);
                    }
                }
            ]);

            app.run(["autoTopService", function(autoTopService) {
                autoTopService.initialize();
            }]);

            /**
             * Initialize the application
             * @return {ngModule} Main module.
             */
            app.init = function() {

                var appContent = angular.element("#content");

                if (appContent[0] !== null) {

                    // apply the app after requirejs loads everything
                    angular.bootstrap(appContent[0], ["App"]);
                }

                // Chaining
                return app;
            };

            // We can now run the bootstrap for the application
            app.init();

        });

        return app;
    };
});
