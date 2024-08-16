/*
# templates/update_config/index.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize"
    ],
    function(angular, $, _, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.updateConfig",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/config",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
