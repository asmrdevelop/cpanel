/*
# cjt/directives/validateEqualsDirective.js          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// TODO: Maybe move to the validators folder

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        // Get the current application
        var module = angular.module("cjt2.directives.validateEquals", []);

        /**
         * Directive that compares the field value with another value.
         * @attribute {String}  validateEquals Model to compare against.
         * @example
         *
         * For an optional fields comparison:
         * <form name="form">
         * <input name="password" ng-model="password">
         * <input name="confirm" ng-model="confirm" validate-equals="form.password">
         * <button type="submit" ng-disabled="form.$invalid">Submit</button>
         * </form>
         *
         * For an required fields comparison:
         * <form name="form">
         * <input name="password" ng-model="password" required>
         * <input name="confirm" ng-model="confirm" validate-equals="form.password">
         * <button type="submit" ng-disabled="form.$invalid">Submit</button>
         * </form>
         *
         * Note: If the field being watch is required and either it or the field with this
         * directive attached is empty, it makes the form invalid.
         */
        module.directive("validateEquals", function() {
            return {
                require: "ngModel",
                link: function(scope, elm, attrs, ngModel) {

                    /**
                     * Validate that the value is equal to the requested value
                     * @param  {String} value Value to test.
                     * @return {Boolean}      true if the passed in value is equal to the registered value.
                     */
                    ngModel.$validators.validateEquals = function validateEquals(value) {

                        var ngOtherModel = getNgOtherModel();
                        if (!ngOtherModel) {

                            // Early in the page life cycle
                            return true;
                        }

                        var thisIsEmpty = ngModel.$isEmpty(value);
                        var otherIsEmpty = ngOtherModel.$isEmpty(ngOtherModel.$viewValue);
                        if (thisIsEmpty && otherIsEmpty) {

                            // If both inputs are empty, it's valid if the other field is not required.
                            return !ngOtherModel.$validators.required;
                        } else {

                            return (

                                /**
                                 * If we have an asyncValidator in progress then we should validate against the
                                 * viewValue to present immediate results. This validator will be re-evaluated if
                                 * the modelValue changes after the asyncValidation because of the $watchGroup.
                                 *
                                 * We should also use the viewValue if the other model is marked as invalid, to
                                 * make sure that we're validating against an actual value instead of undefined.
                                 * While these results don't actually matter because the other model will need to
                                 * be modified for it to be valid, it would feel awkward without feedback from
                                 * this validator.
                                 */
                                (ngOtherModel.$pending || ngOtherModel.$invalid) ?
                                    (value === ngOtherModel.$viewValue) :
                                    (value === ngOtherModel.$modelValue)
                            );
                        }
                    };

                    /**
                     * Check for changes on the comparison value and validate if changed. We watch the
                     * viewValue to ensure that users get immediate feedback before validators run. We
                     * watch the modelValue to ensure that models that don't pass validation or get
                     * transformed by parsers/formatters are properly validated.
                     */
                    scope.$watchGroup([
                        function() {
                            var ngOtherModel = getNgOtherModel();
                            return ngOtherModel && ngOtherModel.$viewValue;
                        },
                        function() {
                            var ngOtherModel = getNgOtherModel();
                            return ngOtherModel && ngOtherModel.$modelValue;
                        }
                    ], function() {
                        ngModel.$validate();
                    });

                    // We need to use this getter for form controls that are added later in the life cycle.
                    var _ngOtherModel;
                    function getNgOtherModel() {
                        if (!_ngOtherModel) {
                            _ngOtherModel = scope.$eval(attrs.validateEquals);
                        }
                        return _ngOtherModel;
                    }
                }
            };
        });
    });
