/*
* multiphp_manager/index.js                 Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        "use strict";
        return function() {

            // First create the application
            angular.module("App", ["ngRoute", "ui.bootstrap", "cjt2.cpanel", "cpanel.multiPhpManager.service"]);

            // Then load the application dependencies
            var app = require(
                [

                    // Application Modules
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/views/config"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.firstLoad = {
                        phpAccountList: true
                    };

                    // Setup Routing
                    app.config(["$routeProvider", "$locationProvider", "$animateProvider",
                        function($routeProvider, $locationProvider, $animateProvider) {

                            // This prevents performance issues
                            // when the queue gets large.
                            // cf. https://docs.angularjs.org/guide/animations#which-directives-support-animations-
                            $animateProvider.classNameFilter(/INeverWantThisToAnimate/);

                            // Setup the routes
                            $routeProvider.when("/config/", {
                                controller: "config",
                                templateUrl: CJT.buildFullPath("multiphp_manager/views/config.html.tt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/config/"
                            });
                        }
                    ]);

                    BOOTSTRAP("#content", "App");

                });

            return app;
        };
    }
);
