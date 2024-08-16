/* global define */
define([
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileType", [function() {
            function checkType(file, types) {
                var valid = false;
                angular.forEach(types, function(type) {
                    valid = valid || file.type === type;
                });
                return valid;
            }
            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {

                        // Check for empty files being uploaded
                            if (file.size === 0) {
                                $ngModelCtrl.$setValidity("filesize", false);
                            } else {
                                $ngModelCtrl.$setValidity("filesize", true);
                            }

                            if (!checkType(file, $scope.$eval($attrs.fileType))) {
                                $ngModelCtrl.$setValidity("filetype", false);
                            } else {
                                $ngModelCtrl.$setValidity("filetype", true);
                            }
                        }
                    });
                }
            };
        }]);
});
