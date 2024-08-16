/*
# mail/spam/directives/multiFieldEditor.js           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        var app = angular.module("cjt2.directives.multiFieldEditor", []);

        app.directive("multiFieldEditor", ["$log", function($log) {
            function _link(scope, element, attr) {
                scope.addNewLabel = scope.addNewLabel ? scope.addNewLabel : LOCALE.maketext("Add A New Item");
            }

            function _multiFieldEditorController($scope) {
                this.minValuesCount = $scope.minValuesCount || 0;
                this.ngModel = $scope.ngModel ? $scope.ngModel : new Array($scope.minValuesCount);

                if (this.ngModel.length < this.minValuesCount) {
                    this.ngModel.length = this.minValuesCount;
                }

                this.removeRow = function(rowKey) {
                    if (!this.ngModel.length) {
                        $log.error("Attempting to remove an item from the MFE when no items are present. Likely this is because of a detachment of the referenced array. Did you do an array= somewhere?");
                    }
                    this.ngModel.splice(rowKey, 1);
                };

                var itemBeingAdded = -1;

                this.addRow = function() {
                    itemBeingAdded = this.ngModel.length;
                    this.ngModel.length++;
                };

                this.getAddingRow = function() {
                    return itemBeingAdded;
                };

                angular.extend($scope, this);
            }

            var RELATIVE_PATH = "libraries/cjt2/directives/";
            var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

            var TEMPLATE = TEMPLATES_PATH + "multiFieldEditor.phtml";

            return {
                templateUrl: TEMPLATE,
                restrict: "EA",
                require: ["ngModel"],
                transclude: true,
                scope: {
                    "parentID": "@id",
                    "minValuesCount": "=?",
                    "addNewLabel": "@?",
                    "ngModel": "="
                },
                link: _link,
                controller: ["$scope", _multiFieldEditorController]
            };
        }]);
    }
);
