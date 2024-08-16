/*
# templates/contact_manager/index.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define:false */

define(
    [
        "angular",
        "cjt/core",
        "uiBootstrap",
        "cjt/directives/searchDirective",
        "cjt/modules",
        "cjt/decorators/growlDecorator",
    ],
    function(angular, CJT) {
        "use strict";

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "cjt2.directives.search",
                "cjt2.whm",
                "angular-growl",
                "whm.contactManager.indexService"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/controllers/mainController",
                    "app/directives/indeterminate",
                ], function(BOOTSTRAP) {

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
