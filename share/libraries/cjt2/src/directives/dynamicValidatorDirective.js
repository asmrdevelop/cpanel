/*
# templates/mod_security/views/dynamicValidatorDirective.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// TODO: Move to the validators folder

define(
    [
        "angular",
        "lodash",
        "cjt/validator/validator-utils"
    ],
    function(angular, _, UTILS) {

        "use strict";

        /**
         * Run a single rule.
         * @param  {Any} value           Value to check.
         * @param  {Object} rule         Rule to run, includes a name and optional argument.
         * @param  {ValidationResult} result       ValidationResult to fill in...
         * @param  {Function} validateFn Validation function to call.
         * @return {Boolean}             true if valid, false otherwise.
         */
        var runRule = function(value, rule, result, validateFn) {
            return validateFn(value, rule.name, rule.arg, result);
        };

        /**
         * Normalize a single rule.
         * @param  {Object|String} rule If an object, its formatted as below. If a string, its just a validation rule name.
         *     @param {String} [rule.name] Name of the validator.
         *     @param {Object} [rule.arg]  Argument to the validator.
         * @return {Object}    Rule with both name and arg properties fully expanded.
         */
        var normalizeRule = function(rule) {
            if (_.isString(rule)) {
                return {
                    name: rule,
                    arg: "",
                };
            } else {
                return rule;
            }
        };

        /**
         * Normalize the list of rules.
         * @param  {Array} rules List of unnormalized rules.
         * @return {Array}       List of normalized rules. For details see normalizeRule().
         */
        var normalizeRules = function(rules) {
            for (var i = 0, l = rules.length; i < l; i++) {
                rules[i] = normalizeRule(rules[i]);
            }
            return rules;
        };

        /**
         * Runs all the validation rules on the given value.
         * @param  {Array} rules      List of rules to run.
         * @param  {ModelController} ctrl Model controller where we participate in normal validation status stuff
         * @param  {FormController} form  Form controller where extended error details are registered per validator.
         * @param  {Function} validateFn Aggregate validation function with signature:
         *      @param  {Any}    value  Value to check.
         *      @param  {String} name   Name of the test to run. These functions may contain many tests distinguished by the various names passed.
         *      @param  {Any}    [arg]  Optional argument to validation function.
         *      @param  {ValidationResult} result Fully filled in result object.
         *      @return {Boolean} true if valid, false otherwise.
         * @param  {Any} value      Value to check.
         * @return {Any}            Value to return, will be value passed in if valid, or undefined if invalid.
         */
        var runRules = function(rules, ctrl, form, validateFn, value) {
            for (var i = 0, l = rules.length; i < l; i++) {
                var result = UTILS.initializeValidationResult();
                var valid = (ctrl.$pristine && ctrl.$isEmpty(value)) || runRule(value, rules[i], result, validateFn);
                var name = rules[i].name;
                ctrl.$setValidity(name, valid);
                UTILS.updateExtendedReporting(valid, ctrl, form, name, result);
            }

            return value;
        };

        var module = angular.module("cjt2.directives.dynamicValidator", []);

        module.directive("dynamicValidator", function() {
            return {
                restrict: "A",
                require: "ngModel",
                link: function(scope, element, attrs, ctrl) {
                    var rules = attrs["dynamicValidator"] ? scope.$eval(attrs["dynamicValidator"]) : [];
                    var validateFn = scope.$eval(attrs["validateFn"]);
                    var form = element.controller("form");
                    UTILS.initializeExtendedReporting(ctrl, form);

                    if (rules && rules.length) {


                        rules = normalizeRules(rules);

                        // For DOM -> model validation
                        ctrl.$parsers.unshift(function(value) {
                            return runRules(rules, ctrl, form, validateFn, value);
                        });

                        // For model -> DOM validation
                        ctrl.$formatters.unshift(function(value) {
                            return runRules(rules, ctrl, form, validateFn, value);
                        });
                    }
                }
            };
        });
    }
);
