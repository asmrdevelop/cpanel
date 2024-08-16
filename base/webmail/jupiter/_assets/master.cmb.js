/*
# cpanel - base/webmail/jupiter/_assets/master.js  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    'master/master',[
        "angular",
        "cjt/core",
        "uiBootstrap",
    ],
    function(angular) {
        return function() {

            // First create the application
            angular.module("Master", ["ui.bootstrap"]);

            // Then load the application dependencies
            var app = require(
                [

                    // Application Modules
                ], function() {

                    var app = angular.module("Master");

                    /**
                     * Initialize the application
                     * @return {ngModule} Main module.
                     */
                    app.init = function() {

                        angular.element("#masterAppContainer").ready(function() {

                            var masterAppContainer = angular.element("#masterAppContainer");
                            if ( masterAppContainer[0] !== null ) {

                                // apply the app after requirejs loads everything
                                angular.bootstrap(masterAppContainer[0], ["Master"]);
                            }

                        });

                        // Chaining
                        return app;
                    };

                    // We can now run the bootstrap for the application
                    app.init();

                });

            return app;
        };
    }
);

