/*
# whostmgr/docroot/templates/cpanel_customization/directive/fileType.js     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define([
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileType", [function() {
            function checkType(file, types) {
                var valid = false;
                var fileType = file.type;

                // IE doesn't return file.type for some MIME types.
                // For example it doesn't for 'json' type.
                // FIX: For 'json' in IE browsers.
                // If (file.type is empty){
                //    match file extension with requested type.
                // }
                // NOTE: This is not a fix for all but will cover at least JSON.
                if (fileType === "") {
                    var matchArr = file.name.match(/\.((?:.(?!\.))+)$/);
                    fileType = (matchArr.length > 0) ? matchArr[1] : "";

                    // Hack for json type
                    if (fileType === "json") {
                        fileType = "application/" + fileType;
                    }
                }

                valid = types.some(function(type) {
                    return type === fileType;
                });
                return valid;
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
                }
            };
        }]);
});
