/*
# cjt/directives/triStateCheckbox.js              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// http://plnkr.co/edit/PTnzedhD6resVkApBE9K?p=preview
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

        var module = angular.module("cjt2.directives.triStateCheckbox", [
            "cjt2.templates"
        ]);

        /**
         * The triStateCheckbox is used to create a check all style controller
         * check-box for a group of check boxes.
         *
         * @directive
         * @directiveType Elements
         * @attribute {Binding} checkboxes Dataset controlling the dependent check-boxes
         */
        module.directive("triStateCheckbox", function() {

            var RELATIVE_PATH = "libraries/cjt2/directives/triStateCheckbox.phtml";

            return {
                replace: true,
                restrict: "E",
                scope: {
                    checkboxes: "=",
                    ngChange: "&",
                    useInt: "@"
                },
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                controller: ["$scope", "$element",
                    function($scope, $element) {
                        $scope.toggled = false;

                        /**
                         * Handler method when changes to the master controller occur.
                         */
                        $scope.masterChange = function() {
                            if (typeof $scope.checkboxes === "undefined") {
                                return;
                            }

                            var setting;
                            if ($scope.master === true) {
                                setting = $scope.useInt ? 1 : true;
                            } else {
                                setting = $scope.useInt ? 0 : false;
                            }

                            for (var i = 0, len = $scope.checkboxes.length; i < len; i++) {
                                $scope.checkboxes[i].selected = setting;
                            }
                            $scope.toggled = true;

                            if ($scope.ngChange) {
                                $scope.ngChange();
                            }
                        };

                        // Use a deep watch for changes to the model behind the related checkboxes
                        $scope.$watch("checkboxes", function() {

                            if (typeof $scope.checkboxes === "undefined") {
                                return;
                            }

                            // shortcut the watch if we just toggled all
                            if ($scope.toggled) {
                                $scope.toggled = false;
                                return;
                            }

                            var atLeastOneSet = false;
                            var allChecked = true;

                            for (var i = 0, len = $scope.checkboxes.length; i < len; i++) {
                                if ($scope.checkboxes[i].selected) {
                                    atLeastOneSet = true;
                                } else {
                                    allChecked = false;
                                }
                            }

                            if (allChecked) {
                                $scope.master = true;
                                $element.prop("indeterminate", false);
                            } else {
                                $scope.master = false;
                                $element.prop("indeterminate", atLeastOneSet);
                            }
                        }, true);
                    }
                ]
            };
        });
    }
);
