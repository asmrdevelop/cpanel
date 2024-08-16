/*
# whostmgr/docroot/templates/userlist/index.js       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/modules",
        "ngSanitize",
        "uiBootstrap",
        "cjt/templates"
    ],
    function(angular, CJT, LOCALE) {
        "use strict";

        CJT.config.html5Mode = false;

        return function() {

            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/validator/ip-validators",
                    "cjt/directives/validationContainerDirective",
                    "cjt/directives/validationItemDirective",
                    "cjt/directives/whm/userDomainListDirective"
                ],
                function(bootstrap) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.controller("UserListController", ["$scope", function($scope) {

                        var editLockedAccounts = {};
                        if (PAGE.childWorkloadAccounts) {
                            PAGE.childWorkloadAccounts.forEach(function(key) {
                                editLockedAccounts[key] = LOCALE.maketext("You must edit this account on the parent node.");
                            });
                        }

                        angular.extend($scope, {
                            domains: PAGE.domains,
                            editLockedAccounts: editLockedAccounts,
                            userRequired: PAGE.userRequired.toString() === "1",
                            selectedDomain: null
                        });

                    }]);

                    bootstrap("#userListWidget");

                });

            return app;
        };
    }
);
