/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileSize.js
#                                                  Copyright 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
    "app/constants",
], function(angular, CONSTANTS) {
    "use strict";

    var module = angular.module("customize.directives.fileSize", []);

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    module.directive("fileSize", [function() {

        return {
            restrict: "A",
            require: "ngModel",
            priority: 10,
            link: function link($scope, $element, $attrs, $ngModelCtrl) {

                /**
                 * Helper used to mock behavior in tests
                 * @param {HtmlFileInput} el
                 * @returns {File}
                 */
                $scope._getFiles = function(el) {
                    return el.files;
                };

                $element.bind("change", function() {
                    var file = $scope._getFiles(this)[0];
                    if (file) {

                        // Check for empty files being uploaded
                        if (file.size === 0) {
                            $ngModelCtrl.$setValidity("fileSize", false);
                        } else {
                            $ngModelCtrl.$setValidity("fileSize", true);
                        }
                    }
                });
            },
        };
    }]);

    module.directive("fileMaxSize", [function() {

        return {
            restrict: "A",
            require: "ngModel",
            priority: 10,
            link: function link($scope, $element, $attrs, $ngModelCtrl) {
                $scope.maxSize = parseInt($attrs["fileMaxSize"]) || CONSTANTS.MAX_FILE_SIZE;

                /**
                 * Helper used to mock behavior in tests
                 * @param {HtmlFileInput} el
                 * @returns {File}
                 */
                $scope._getFiles = function(el) {
                    return el.files;
                };

                $element.bind("change", function() {
                    var file = $scope._getFiles(this)[0];
                    if (file) {

                        // Check for large files being uploaded
                        if (file.size > $scope.maxSize) {
                            $ngModelCtrl.$setValidity("fileMaxSize", false);
                        } else {
                            $ngModelCtrl.$setValidity("fileMaxSize", true);
                        }
                    }
                });
            },
            controller: ["$scope", function($scope) {
                this.getMaxSize = function() {
                    return $scope.maxSize;
                };
            }],
        };
    }]);
});
