/*
 * templates/multiphp_manager/views/conversion.js        Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "conversion",
            ["$scope", "$sce", "$routeParams",
                function($scope, $sce, $routeParams) {
                    $scope.buildId = $routeParams.buildId;

                    // Create iframe to load the tailing cgi script
                    $scope.tailingUrl = CPANEL.security_token + "/cgi/process_tail.cgi?process=ConvertToFPM&build_id=" + $scope.buildId;
                    $scope.tailingUrl = $sce.trustAsResourceUrl($scope.tailingUrl);
                }
            ]);
        return controller;
    }
);
