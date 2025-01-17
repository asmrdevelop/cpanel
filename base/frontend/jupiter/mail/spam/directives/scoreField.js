/*
# mail/spam/directives/scoreField.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "angular-chosen"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        var app = angular.module("cpanel.apacheSpamAssassin.directives.scoreField", [
            "localytics.directives"
        ]);

        app.directive("scoreField", ["$timeout", function($timeout) {

            function _link($scope, element) {

                $scope.scoreType = null;
                $scope.selectedScoreType = null;
                $scope.scoreValue = null;

                $scope.$watch("selectedScoreType", function(newValue, oldValue) {
                    if ((newValue) && (($scope.scoreValue === null) || ($scope.scoreType !== newValue.key))) {
                        $scope.scoreType = newValue.key;
                        $scope.scoreValue = newValue.score;
                    }
                });
            }

            function _scoreFieldController($scope) {

                ["scoreType", "scoreValue"].forEach(function(key) {
                    $scope.$watch(key, function(newValue, oldValue) {
                        if (($scope.scoreType) && ($scope.scoreValue !== null)) {
                            $scope.ngModel = $scope.scoreType + " " + $scope.scoreValue;
                        }
                    });
                });

                $scope.modelUpdated = function() {
                    if ($scope.ngModel) {
                        var modelParts = $scope.ngModel.split(" ");
                        $scope.scoreType = modelParts[0];
                        angular.forEach($scope.scoreTypes, function(scoreType) {
                            if (scoreType.key === $scope.scoreType) {
                                $scope.selectedScoreType = scoreType;
                            }
                        });
                        $scope.scoreValue = isNaN(modelParts[1]) ? null : Number(modelParts[1]);
                    }
                };
                $scope.$watch("ngModel", $scope.modelUpdated);
                $scope.modelUpdated();

            }

            var TEMPLATE_PATH = "directives/scoreField.phtml";
            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                require: ["ngModel"],
                transclude: true,
                scope: {
                    "scoreTypes": "=",
                    "ngModel": "=",
                    "parentID": "@id"
                },
                link: _link,
                controller: ["$scope", _scoreFieldController]
            };
        }]);
    }
);
