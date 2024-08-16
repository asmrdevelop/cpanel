/*
# cpanel - base/webmail/jupiter/account_preferences/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    [
        "angular",
        "app/services/accountPrefs",
        "app/views/main",
        "cjt/modules",
        "cjt/directives/alertList",
        "cjt/services/APICatcher",
        "ngRoute",
        "uiBootstrap",
    ],
    function(angular, AccountPrefsService, MainView) {

        "use strict";

        var MODULE_NAME = "webmail.accountPrefs";

        return function() {

            // First create the application
            var appModule = angular.module(MODULE_NAME, [
                "ngRoute",
                "ui.bootstrap",
                "cjt2.webmail",
                AccountPrefsService.namespace,
                MainView.namespace,
            ]);

            appModule.value("EMAIL_ADDRESS", PAGE.emailAddress);
            appModule.value("DISPLAY_EMAIL_ADDRESS", PAGE.displayEmailAddress);
            appModule.value("RESOURCE_TEMPLATE", "views/_resources.ptt");

            // Then load the application dependencies
            var app = require(["cjt/bootstrap"], function(BOOTSTRAP) {

                appModule.config([
                    "$routeProvider",
                    function($routeProvider) {

                        $routeProvider.when("/", {
                            controller: MainView.controller,
                            templateUrl: MainView.template,
                            resolve: MainView.resolver,
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/",
                        });
                    },
                ]);

                BOOTSTRAP("#mainContent", MODULE_NAME);

            });

            return app;
        };
    }
);
