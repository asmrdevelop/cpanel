/*
# autossl/directives/starRating.js                                            Copyright(c) 2020 cPanel, L.L.C.
#                                                                                      All rights reserved.
# copyright@cpanel.net                                                                    http://cpanel.net
# This code is subject to the cPanel license.                            Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {

        "use strict";

        var module = angular.module("whostmgr.autossl.starRating", []);

        var TEMPLATE_PATH = "directives/starRating.phtml";

        module.directive("starRating", function() {

            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                replace: true,
                transclude: true,
                scope: {
                    max: "=",
                    rating: "="
                },
                controller: ["$scope", function($scope) {

                    function _buildStars() {
                        $scope.stars = [];
                        while ($scope.stars.length < $scope.max) {
                            $scope.stars.push($scope.rating > $scope.stars.length ? 1 : 0);
                        }
                    }

                    $scope.$watch("max", _buildStars);
                    $scope.$watch("rating", _buildStars);

                    _buildStars();
                }]
            };
        });
    }
);
