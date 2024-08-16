/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileType.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
], function(angular) {
    "use strict";

    var module = angular.module("customize.directives.fileType", []);

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    module.directive("fileType", [function() {
        function checkType(file, types) {
            return types.some(function(type) {
                return file.type === type;
            });
        }
        return {
            restrict: "A",
            require: "ngModel",
            link: function link($scope, $element, $attrs, $ngModelCtrl) {
                $element.bind("change", function() {
                    var file = this.files[0];
                    if (file && !checkType(file, $scope.$eval($attrs.fileType))) {
                        $ngModelCtrl.$setValidity("filetype", false);
                    } else {
                        $ngModelCtrl.$setValidity("filetype", true);
                    }
                });
            },
        };
    }]);
});
