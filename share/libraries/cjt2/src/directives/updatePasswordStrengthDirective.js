/*
# cjt/directives/updatePasswordStrengthDirective.js Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.updatePasswordStrength", []);

        module.directive("updatePasswordStrength", function() {
            return {
                restrict: "A",
                require: "ngModel",
                replace: false,
                scope: {
                    fieldId: "@?fieldId"
                },
                link: function(scope, element, attrs, ngModel) {
                    if (!ngModel) {
                        return;
                    }

                    ngModel.$render = function() {
                        element.attr("value", ngModel.$viewValue || "");
                    };

                    // Monitor for the passwordStrengthChange event
                    scope.$on("passwordStrengthChange", function(evt, result) {
                        if ( ( scope.fieldId && result.id === scope.fieldId ) || // Matches the id if provided
                             ( !scope.fieldId ) ) {                              // Or id check is skipped if not provided
                            var strength = result.strength;
                            ngModel.$setViewValue(strength);
                        }
                    });
                }
            };
        });

    });
