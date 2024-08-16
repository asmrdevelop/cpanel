/*
# whostmgr/docroot/templates/cpanel_customization/directive/fileSize.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */
define([
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileSize", [function() {

            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {

                        // Check for empty files being uploaded
                            if (file.size === 0) {
                                $ngModelCtrl.$setValidity("fileSize", false);
                            } else {
                                $ngModelCtrl.$setValidity("fileSize", true);
                            }
                        }
                    });
                }
            };
        }]);
});
