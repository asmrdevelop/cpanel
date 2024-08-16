/*
# domains/views/main.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/** @namespace cpanel.domains.views.main */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/views/ROUTES",
        "cjt/decorators/alertAPIReporter",
        "cjt/directives/alertList",
        "cjt/directives/toggleSwitchDirective",
        "cjt/services/alertService"
    ],
    function(angular, _, LOCALE, ROUTES) {

        "use strict";

        var app = angular.module("cpanel.domains");

        var controller = app.controller(
            "main",
            ["$scope", "$rootScope", "$location", "alertService",
                function($scope, $rootScope, $location, $alertService) {

                    $rootScope.$on("$routeChangeStart", function() {
                        $scope.loading = true;
                        $alertService.clear("danger");
                    });


                    $rootScope.$on("$routeChangeSuccess", function(event, current) {
                        $scope.loading = false;
                    });

                    $rootScope.$on("$routeChangeError", function() {
                        $scope.loading = false;
                    });
                }
            ]
        );

        /*
        // The following lines are a workaround for CPANEL-3887. Having a dummy mt call
        // ensures that the minified version of this file is not deleted during a build.
        require(["cjt/util/locale"], function(LOCALE) {
            LOCALE.maketext("Enabled");
        });
        */

        return controller;
    }
);
