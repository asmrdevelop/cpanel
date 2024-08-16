/*
# cjt/directives/deepTriStateCheckbox.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// https://gist.github.com/arnab-das/6129431
// Used with permission.
// ------------------------------------------------------------
// 1) Consider converting to use ng-model instead of custom
// binding.
// ------------------------------------------------------------

define(
    [
        "angular",
        "cjt/core",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        var module = angular.module("cjt2.directives.deepTriStateCheckbox", [
            "cjt2.templates"
        ]);

        /**
         * The deepTriStateCheckbox is used to create a check all style controller
         * check box for a group of check boxes that includes one or more nested child
         * collections of check boxes.
         *
         * @directive
         * @directiveType Elements
         * @attribute {Binding} checkboxes Dataset controlling the dependent check-boxes
         */
        module.directive("deepTriStateCheckbox", function() {
            var RELATIVE_PATH = "libraries/cjt2/directives/triStateCheckbox.phtml";

            return {
                replace: true,
                restrict: "E",
                scope: {
                    checkboxes: "="
                },
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                controller: ["$scope", "$element", function($scope, $element) {

                    /**
                     * Handler method when changes to the master controller occur.
                     */
                    $scope.masterChange = function() {
                        if ($scope.master) {
                            angular.forEach($scope.checkboxes, function(cb) {
                                cb.selected = true;
                                angular.forEach(cb.children, function(cb) {
                                    cb.selected = true;
                                });
                            });
                        } else {
                            angular.forEach($scope.checkboxes, function(cb) {
                                cb.selected = false;
                                angular.forEach(cb.children, function(cb) {
                                    cb.selected = false;
                                });
                            });
                        }
                    };

                    // Watch for changes to the model behind the related checkboxes
                    $scope.$watch("checkboxes", function() {
                        var allSet = true,
                            allClear = true;

                        angular.forEach($scope.checkboxes, function(cb) {
                            if (cb.children) {
                                angular.forEach(cb.children, function(cb) {
                                    if (cb.selected) {
                                        allClear = false;
                                    } else {
                                        allSet = false;
                                    }
                                });
                            } else if (cb.selected) {
                                allClear = false;
                            } else {
                                allSet = false;
                            }
                        });

                        if (allSet)        {

                            // Handle all set
                            $scope.master = true;
                            $element.prop("indeterminate", false);
                        } else if (allClear) {

                            // Handle all clear
                            $scope.master = false;
                            $element.prop("indeterminate", false);
                        } else {

                            // Handel indeterminate
                            $scope.master = false;
                            $element.prop("indeterminate", true);
                        }
                    }, true);
                }]
            };
        });
    }
);
