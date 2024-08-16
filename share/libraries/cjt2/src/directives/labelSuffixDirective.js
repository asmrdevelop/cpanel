/*
 * cpanel - share/libraries/cjt2/src/directives/labelSuffixDirective.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

/**
 * Directive that shows the validation status of an input box in a form.
 *
 * Default behavior with no attributes specified:
 *   - For regular input fields: Do nothing
 *   - For required input fields: Show an asterisk when not filled out
 *
 * Required attributes
 *
 * for=...
 *   - Given an element id, associates the label-suffix with that input
 *     element. Think of this as analogous to 'for' in label itself.
 *
 * Optional attributes
 *
 * show-validation-status
 *   - Enables the display of the 3-part validation status, which includes:
 *       1. (For async validators only) A spinner to let the user know the
 *          validation is still pending.
 *       2. An X to let the user know the input is invalid.
 *       3. A check mark (√) to let the user know the input is valid.
 *
 * @example
 *
 * This directive mimics the attribute naming of labels, so you can say:
 *
 *   <label for="myField">
 *       [% locale.maketext('My Field') %]
 *       <label-suffix for="myField" show-validation-status></label-suffix>
 *   </label>
 *   <input name="myField .......
 *
 * Note that it is recommended for styling reasons, but not technically required,
 * to place the label-suffix inside of the label.
 */
define([
    "angular",
    "cjt/core",
    "cjt/util/locale",
    "cjt/directives/spinnerDirective",
],
function(angular, CJT, LOCALE) {
    var module = angular.module("cjt2.directives.labelSuffix", [
        "cjt2.templates"
    ]);
    var RELATIVE_PATH = "libraries/cjt2/directives/labelSuffix.phtml";
    module.directive("labelSuffix", ["spinnerAPI", "$timeout", function(spinnerAPI, $timeout) {
        return {
            restrict: "E", // label-suffix currently only works as a standalone element, but it could probably
            // be adapted pretty easily to fit directly as an attribute on the label itself.
            templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
            scope: {
                fieldId: "@for",
            },
            require: "^form",
            link: function(scope, element, attrs, form) {
                scope.showValidationStatus = ( typeof attrs["showValidationStatus"] !== "undefined" );

                if (!scope.fieldId) {
                    throw new Error("You must provide the 'for' attribute for label-suffix.");
                }

                /* All of this setup needs to be done in a 0 ms timeout so that it gets postponed until the
                     * next digest cycle. This allows sibling directives that create inputs to be initialized in
                     * time for us to interact with them.
                     *
                     * For example:
                     *
                     *   <label for="foo">
                     *       My Input <label-suffix for="foo"></label-suffix>
                     *   </label>
                     *   <my-input id="foo" name="foo" required></my-input>
                     *
                     * We ran into a problem like this with passwordFieldDirective, which wasn't consistently
                     * initializing the input it creates in time for this directive to check the required status.
                     */
                scope.form = form; // For use with the scope watch that starts/stops the spinner

                /* For simplicity of being able to set up the watch without necessarily being able to locate
                     * the element itself yet (if it's added by a directive that hasn't been processed yet), we're
                     * going to assume that the field name is exactly the same as its id. This may not always be
                     * the case, but it should usually be. If it turns out that this is too much of a limitation,
                     * feel free to find an alternative approach, as long as it doesn't break compatibility with
                     * directives like passwordFieldDirective that delay creation of inputs until after this one
                     * has already finished its setup. */
                scope.fieldName = scope.fieldId;

                scope.spinnerId = "validationSpinner_" + scope.fieldName;

                scope.showAsterisk = function() {
                    return scope._findInputElem()           &&
                               scope.inputElem.prop("required") &&
                               (form[scope.fieldName].$pristine || !scope.inputElem.val());
                };

                scope.isValid = function() {
                    return  scope.showValidationStatus      &&
                                scope._findInputElem()          &&
                                scope.inputElem.val()           &&
                               !form[scope.fieldName].$pristine &&
                                form[scope.fieldName].$valid    &&
                               !form[scope.fieldName].$pending;
                };

                scope.isInvalid = function() {
                    return  scope.showValidationStatus      &&
                                scope._findInputElem()          &&
                                scope.inputElem.val()           &&
                               !form[scope.fieldName].$pristine &&
                               !form[scope.fieldName].$valid    &&
                               !form[scope.fieldName].$pending;
                };

                scope.text = function(name) {
                    switch (name) {
                        case "required":
                            return LOCALE.maketext("This value is required.");
                        case "valid":
                            return LOCALE.maketext("The value you entered is valid.");
                        case "invalid":
                            return LOCALE.maketext("The value you entered is not valid.");
                        case "validating":
                            return LOCALE.maketext("Validating …");
                        default:
                            return LOCALE.maketext("An unknown problem occurred with the validation.");
                    }
                };

                scope.$watch("form." + scope.fieldName + ".$pending", function(pending) {
                    if (scope.showValidationStatus) {
                        if (pending) {
                            spinnerAPI.start(scope.spinnerId);
                        } else {
                            spinnerAPI.stop(scope.spinnerId);
                        }
                    }
                });

                scope._findInputElem = function() {
                    if (!scope.inputElem || !scope.inputElem[0]) {
                        scope.inputElem = angular.element("#" + scope.fieldId);
                    }
                    return scope.inputElem && !!scope.inputElem[0];
                };
            }
        };
    }]);
}
);
