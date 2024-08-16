/*
# cjt/diag/routeDirective.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/templates"
    ],
    function(angular, CJT) {

        var RELATIVE_PATH = "libraries/cjt2/diag/routeDirective.phtml";

        var module = angular.module("cjt2.diag.route", [
            "cjt2.templates"
        ]);

        module.controller("diagRouteController", [
            "$scope",
            "$routeParams",
            "$route",
            "$window",
            "$location",
            function( $scope, $routeParams, $route, $window, $location) {
                $scope.$location = $location;
                $scope.$window = $window;
                $scope.$route = $route;
                $scope.$routeParams = $routeParams;
            }
        ]);

        module.directive("diagRoute", [ function() {
            return {
                restrict: "EA",
                replace: true,
                scope: true,
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                controller: "diagRouteController",
                link: function(scope, element, attr) {}
            };
        }]);

    }
);
