/*
# backup_user_selection/index.js                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "app/services/backupUserSelectionService",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/directives/callout"
    ],
    function(angular, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.backupUserSelection", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "angular-growl",
                "cjt2.whm",
                "whm.backupUserSelection.backupUserSelectionService.service"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/views/backupUserSelectionView",
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.backupUserSelection");
                    app.value("PAGE", PAGE);


                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/backupUserSelectionView", {
                                controller: "backupUserSelectionView",
                                templateUrl: "views/backupUserSelectionView.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/backupUserSelectionView"
                            });
                        }
                    ]);

                    var appContent = angular.element("#pageContainer");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        BOOTSTRAP(appContent[0], "whm.backupUserSelection");
                    }

                });

            return app;
        };
    }
);
