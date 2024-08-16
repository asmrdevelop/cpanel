/*
# cjt/directives/validationItemDirective.js          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/core",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        "use strict";

        var module = angular.module("cjt2.directives.validationItem", [
            "cjt2.templates"
        ]);

        /**
         * Directive that shows a alert.
         * @example
         *
         * To bind an item to an standard validation error:
         *
         *   <li validation-item field-name="textField" validation-name="required">
         *     The textField is required.
         *   </li>
         *
         * To bind an item to an extended validation error.
         *
         *   <li validation-item field-name="textField" validation-name="custom">
         *   </li>
         *
         * NOTE: Assumes that some custom validator adds the string to $error_details collection.
         *
         * To bind an item manually:
         *
         *   <li validation-item ng-show="form.textField.$error.required">
         *   </li>
         *
         * To supress the icon and use custom styling you can use the following:
         *
         *   <li validation-item field-name="textField" validation-name="custom" no-icon prefix-class='bullets'>
         *   </li>
         *
         * This is useful when you take over rendering and want items that are subitems of a less specific error.
         */
        module.directive("validationItem", [ function() {
            var ct = 0;
            var RELATIVE_PATH = "libraries/cjt2/directives/validationItem.phtml";

            /**
             * Dynamically fetch and cache the field. Caches the field in scope
             * along with the needed errors and extendedErrors collections.
             *
             * @method  _attachField
             * @private
             * @param  {ngForm} form      Form to which the field is attached.
             * @param  {String} fieldName Name of the field we are monitoring.
             * @param  {Scope}  scope     Scope
             * @return {ngField}
             */
            function _attachField(form, fieldName, scope) {
                var field = scope.field;
                if (!field) {

                    // Bail if there is no form to check against.
                    // We check the return in other places.
                    if (form === void 0) {
                        return null;
                    }

                    field = form[fieldName];
                    if (field) {
                        scope.field = field;
                        scope.errors = field.$error;
                        scope.extendedErrors = field.$error_details;
                    }
                }
                return field;
            }

            return {
                restrict: "EA",
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                transclude: true,
                replace: true,
                scope: true,
                link: function( scope, element, attrs) {
                    var prefix = scope.$eval(attrs.prefix) || attrs.prefix || "validator";
                    var prefixClass = scope.$eval(attrs.prefixClass) || attrs.prefixClass || "";

                    var showWhenPristine = scope.$eval(attrs.showWhenPristine) || false;
                    var form = element.controller("form");
                    var showIcon = angular.isDefined(attrs.noIcon) ? false : true;

                    var fieldName;
                    if (attrs.fieldName) {
                        fieldName = scope.$eval(attrs.fieldName) || attrs.fieldName;
                        _attachField(form, fieldName, scope);
                    }

                    var _validationName = attrs.validationName || "";

                    /**
                     * Helper method to see if we should show the icon or the bullet. When true will show
                     * the standard icon, otherwise the prefix span will show. This allows bullet sublist of
                     * error details.
                     * @method showIcon
                     * @returns {Boolean}
                     */
                    scope.showIcon = function() {
                        return showIcon;
                    };

                    scope.prefixClass = prefixClass;

                    /**
                     * Helper method that can be used to test if the item should be shown.
                     *
                     * @method canShow
                     * @param  {Object} [field]          Optional: Reference to a input field controller.  Retrieve from an ngForm[fieldName]. Defaults to the field set by the field-name attribute.
                     * @param  {String} [validationName] Optional: Name of the validation option to check for validity: ex. require. Defaults to the name set in validation-name attribute.
                     * @return {Boolean}                 true if there is a matching validation error and the field is not pristine, false otherwise.
                     */
                    scope.canShow = function(field, validationName) {
                        field = field || _attachField(form, fieldName, scope);
                        validationName = validationName || _validationName;

                        if (field && (showWhenPristine || !field.$pristine || form.$submitted) && field.$invalid && validationName) {

                            // Use automatic matching logic, probably embedded in a validation container.
                            return field.$error[validationName]; // Show if invalid, hide if valid.
                        } else {

                            // Not using automatic matching logic, so let something else decide to show/hide this.
                            return true;
                        }
                    };

                    /**
                     * Return the text for the item
                     *
                     * @method print
                     * @param  {Object} [field]          Optional: Reference to a input field controller.  Retrieve from an ngForm[fieldName]. Defaults to the field set by the field-name attribute.
                     * @param  {String} [validationName] Optional: Name of the validation option to check for validity: ex. require. Defaults to the name set in validation-name attribute.
                     * @return {String}
                     */
                    scope.print = function(field, validationName) {
                        field = field || _attachField(form, fieldName, scope);
                        validationName = validationName || _validationName;
                        if (field && validationName && field.$error[validationName]) {
                            if (field.$error_details) {
                                var details = field.$error_details.get(validationName);
                                if (details && details.hasMessages() && details.hasMessage(validationName)) {
                                    var entry = details.get(validationName);
                                    if (entry) {
                                        return entry.message;
                                    }
                                }
                            }
                        }
                    };

                    scope.id = prefix + ct++;
                }
            };
        }]);
    }
);
