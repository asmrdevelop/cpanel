/*
* templates/tomcat/index.js                       Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
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
        "uiBootstrap",
        "app/services/configService",
    ],
    function(angular, $, _, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.tomcat", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whm.tomcat.configService"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/config",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.tomcat");

                    // Setup Routing
                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "config",
                                templateUrl: CJT.buildFullPath("tomcat/views/config.ptt"),
                                reloadOnSearch: false
                            })
                                .otherwise({
                                    "redirectTo": "/config"
                                });

                        }
                    ]);

                    BOOTSTRAP(document, "whm.tomcat");

                });

            return app;
        };
    }
);
