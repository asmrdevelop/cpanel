/**
 * base/unprotected/controllers/setPasswordController.js   Copyright(c) 2020 cPanel, L.L.C.
 *                                                                   All rights reserved.
 * copyright@cpanel.net                                                 http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited.
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/passwordFieldDirective"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "setPasswordController", [
                "$scope",
                function($scope) {

                    $scope.password = "";
                    $scope.confirmPassword = "";

                }
            ]
        );

        return controller;
    }
);
