/*
# cjt/directives/validateMinimumPasswordStrength.js Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.directives.minimumPasswordStrength", []);

        /**
         * Directive that checks that the password strength as returned by the backend
         * service is stronger then the minimum strength required.  To use, you must also
         * call the checkPasswordStrength directive.
         * @attribute {Number}  minimumPasswordStrength Minimum strength.
         * @example
         * <input check-password-strength minimum-password-strength="10" />
         */
        module.directive("minimumPasswordStrength", function() {
            return {
                require: "^ngModel",
                replace: false,
                priority: 5,
                scope: false,
                link: function(scope, elm, attrs, ngModelController) {

                    /**
                     * Validate that the strength is >= the minimum strength
                     *
                     * @method validatePasswordStrength
                     * @private
                     * @param {Number} currentPasswordStrength The users current password strength.
                     * @return {Boolean} true if the current strength is greater
                     * than the minimum strength; false otherwise.
                     */
                    function validatePasswordStrength(currentPasswordStrength) {
                        var valid = (currentPasswordStrength >=  scope.minimumPasswordStrength);
                        ngModelController.$setValidity("minimumPasswordStrength", valid);
                    }

                    // Monitor for the passwordStrengthChange event
                    scope.$on("passwordStrengthChange", function(evt, result) {
                        if (( scope.fieldId && result.id === scope.fieldId ) ||  // Matches the id if provided
                            ( !scope.fieldId )) {                                // Or id check is skipped if not provided
                            var strength = result.strength;

                            if (!ngModelController.$validators.required &&
                                !ngModelController.$viewValue) {
                                ngModelController.$setValidity("minimumPasswordStrength", true);
                            } else {

                                // Only validate this rule if there aren't other validation errors present or if the checkStrength directive is pending.
                                // The checkStrenght directive uses an asyncValidator and only runs if all of the synchronous validators pass first.
                                // Other validation errors will set the modelValue to undef, so there is no point showing strength information.
                                ngModelController.$setValidity("minimumPasswordStrength", true);

                                if (ngModelController.$valid || (ngModelController.$pending && ngModelController.$pending.passwordStrength)) {
                                    validatePasswordStrength(strength);
                                }
                            }
                        }
                    });

                    // Get the minimum password strength
                    scope.$watch(attrs.minimumPasswordStrength, function(newValue, oldValue, scope) {
                        scope.minimumPasswordStrength = scope.$eval(attrs.minimumPasswordStrength);
                    });

                    // Initially make it valid
                    ngModelController.$setValidity("minimumPasswordStrength", true);
                }
            };
        });

    });
