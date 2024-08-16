/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileModel.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
], function(angular) {
    "use strict";

    var module = angular.module("customize.directives.fileModel", []);

    // This directive updates the $scope when an <input type="file"> changes.
    // AngularJS ng-model does not keep the state of <input type="file"> linked with $scope.
    module.directive("fileModel", ["$parse", function($parse) {
        return {
            restrict: "A",
            require: "ngModel",
            link: function link($scope, $element, $attrs, $ngModelCtrl) {
                var model = $parse($attrs.fileModel);
                $element.bind("change", function() {
                    var file = this.files[0];
                    if (file) {
                        $scope.$apply(function() {
                            model.assign($scope, file.name);

                            // Mark as dirty
                            $ngModelCtrl.$setViewValue($ngModelCtrl.$modelValue);
                            $ngModelCtrl.$setDirty();
                        });
                    }
                });
            },
        };
    }]);
});
