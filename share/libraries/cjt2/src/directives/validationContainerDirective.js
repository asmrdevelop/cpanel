/*
# cjt/directives/validationContainerDirective.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/core",
        "ngSanitize",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        "use strict";

        var module = angular.module("cjt2.directives.validationContainer", [
            "ngSanitize", "cjt2.templates"
        ]);

        /**
         * Directive that shows a alert.
         * @example
         *
         * To bind to a fields standard and extended validation errors:
         *   <ul validation-container field-name="textField">
         *       <li validation-item field-name="textField" validation-name="required">
         *           The textField is required.
         *       </li>
         *   </ul>
         *
         * To bind to a fields extended validation errors:
         *   <ul validation-container field-name="textField">
         *   </ul>
         *
         * To add a custom prefix to the item ids:
         *   <ul validation-container field-name="textField" prefix="foo">
         *   </ul>
         *
         * To take over rendering of the items manually use:
         *   <style>
         *   .bullet::before {
         *       content: "•";
         *       padding-right: 10px;
         *       font-weight: bold;
         *       font-size: larger;
         *   }
         *   </style>
         *   <ul validation-container field-name="textField" manual>
         *      <validation-item field-name="textField" validation-name="cidr"></validation-item>
         *      <validation-item field-name="textField" validation-name="cidr-details" no-icon prefix-class="bullet"></validation-item>
         *   </ul>
         */
        module.directive("validationContainer", ["$log", function($log) {

            var RELATIVE_PATH = "libraries/cjt2/directives/validationContainer.phtml";

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
                replace: true,
                transclude: true,
                scope: true,
                link: function( scope, element, attrs ) {
                    var form = element.controller("form");
                    var fieldName = scope.$eval(attrs.fieldName) || attrs.fieldName;
                    var manual = angular.isDefined(attrs.manual) ? true : false;
                    var prefix = scope.$eval(attrs.prefix) || attrs.prefix || "validator";
                    var showWhenPristine = scope.$eval(attrs.showWhenPristine) || false;
                    var field = _attachField(form, fieldName, scope);

                    /**
                     * Determine if the item can be shown
                     *
                     * @method canShow
                     * @return {Boolean}
                     */
                    scope.canShow = function() {

                        field = _attachField(form, fieldName, scope);
                        if (!field) {
                            return false;
                        }

                        return (!field.$pristine || showWhenPristine || form.$submitted) && field.$invalid;
                    };

                    /**
                     * Determine if the line item  within the item should be shown
                     *
                     * @method canShowItem
                     * @param  {String} key Validation key name.
                     * @return {Boolean}
                     */
                    scope.canShowItem = function(key) {
                        if (manual) {
                            return false;
                        }

                        field = _attachField(form, fieldName, scope);
                        if (!field) {
                            return false;
                        }

                        return scope.errors[key] !== false && scope.hasExtendedError(key);
                    };

                    /**
                     * Gets a list of all validation failure message objects for the field.
                     *
                     * @method aggregateMessages
                     * @return {Array}   An aggregated list of modified ValidationResult objects that
                     *                   are  given "id" and "validatorName" properties
                     */
                    scope.aggregateMessages = function() {

                        field = _attachField(form, fieldName, scope);
                        var messages = [];

                        angular.forEach(scope.errors, function(isInvalid, validatorName) {
                            var messageSet = _getMessageSet(validatorName);
                            if (isInvalid && messageSet) {
                                var setLength = messageSet.length;
                                messageSet.forEach(function(message) {
                                    message.validatorName = validatorName;

                                    // If there is only a single message from the set, we can use the shorter form of the ID.
                                    // This is mainly here to maintain backwards compatability.
                                    message.id = setLength > 1 ? _generateId(validatorName, message.name) : _generateId(validatorName);
                                    messages.push(message);
                                });
                            } else if (isInvalid) {

                                // Invalid but no message set, provides debug info for developer to fix their validator
                                CJT.debug("[cjt2.directives.validationContainer] “" + validatorName + "” is invalid, but does not have a validation message provided. Ensure inline message was created.");
                            }
                        });

                        return messages;
                    };

                    /**
                     * Gets the set of message objects for a particular validator on the field.
                     *
                     * @method _getMessageSet
                     * @private
                     * @param  {String} validatorName   The name of the validator whose messages you wish to fetch
                     * @return {Array}                  An array of ValidationResult objects
                     */
                    function _getMessageSet(validatorName) {
                        if ((field.$pristine && !showWhenPristine) || field.$valid) {
                            return;
                        }

                        if (field.$error_details) {
                            var details = field.$error_details.get(validatorName);
                            if ( details && details.hasMessages() ) {
                                return details.get();
                            } else {
                                return false;
                            }
                        }
                    }


                    /**
                     * Check if the field has extended error information for the key
                     *
                     * @method hasExtendedError
                     * @param  {String}  key Name of the category to look at.
                     * @return {Boolean}     true if has extended error information, false otherwise.
                     */
                    scope.hasExtendedError = function(key) {
                        field = _attachField(form, fieldName, scope);

                        if (field.$error_details) {
                            var details = field.$error_details.get(key);
                            if ( details && details.hasMessages() ) {
                                return true;
                            }
                        }
                        return false;
                    };

                    /**
                     * Returns a generated id for the item.
                     *
                     * @method _generateId
                     * @private
                     * @param {String} validatorName   The name of the validator
                     * @param {String} [errorName]     Optional. The name of the error/rule within the
                     *                                 validator that prompted its validation failure.
                     *                                 This should be provided if there the validator
                     *                                 adds multiple messages to its ValidationResult.
                     * @return {String}
                     */
                    function _generateId(validatorName, errorName) {
                        if (errorName) {
                            return prefix + "_" + fieldName + "_" + validatorName + "_" + errorName;
                        } else {
                            return prefix + "_" + validatorName;
                        }
                    }
                }
            };
        }]);
    }
);
