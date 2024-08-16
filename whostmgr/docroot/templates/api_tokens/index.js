/*
# cpanel - whostmgr/docroot/templates/api_tokens/index.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require: false, define: false */

define(
    [
        "angular",
        "jquery",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "ngAria",
        "uiBootstrap",
        "app/services/api_tokens",
        "app/filters",
    ],
    function(angular) {
        "use strict";

        return function() {
            angular.module("whm.apiTokens", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ngAnimate",
                "ngAria",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whm.apiTokens.apiCallService",
                "whm.apiTokens.filters",
            ]);
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/views/home",
                    "app/views/edit",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.apiTokens");
                    app.value("PAGE", PAGE);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {
                            $routeProvider.when("/home", {
                                controller: "homeController",
                                controllerAs: "home",
                                templateUrl: "api_tokens/views/home.ptt",
                            });

                            $routeProvider.when("/edit/:name?", {
                                controller: "editController",
                                controllerAs: "edit",
                                templateUrl: "api_tokens/views/edit.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/home",
                            });
                        },
                    ]);

                    BOOTSTRAP(document, "whm.apiTokens");

                });

            return app;
        };
    }
);
