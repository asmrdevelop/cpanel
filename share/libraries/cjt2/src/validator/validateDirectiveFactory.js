/*
# cjt/directives/validateDirectiveFactory.js         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "lodash",
        "angular",
        "cjt/validator/validator-utils"
    ],
    function(_, angular, UTILS) {
        "use strict";

        var module = angular.module("cjt2.validate", []);

        module.config(["$compileProvider", function($compileProvider) {

            // Capture the compileProvider so we can use it in the future
            // to add directives dynamically to the validate module
            module.compileProvider = $compileProvider;
        }]);

        /**
         * Run the validation function and update the model and form state
         * if there are issues.
         *
         * @private
         * @method run
         * @param  {String} name          Name of the validator
         * @param  {ModelController} ctrl Model controller where we participate in normal validation status stuff
         * @param  {FormController} form  Form controller where extended error details are registered per validator.
         * @param  {Function} validateFn  Function to valid the value. Only called if value is not empty.
         * @param  {Any} value            Value to validate.
         * @param  {Any} [argument]       Optional argument to the validation function.
         * @param  {Scope} [scope]        The directive scope. Helpful if you want to $eval the argument.
         * @return {Boolean}              true if the value is valid, false otherwise.
         */
        var run = function(name, ctrl, form, validateFn, value, argument, scope) {

            if (ctrl.$isEmpty(value)) {
                return true;
            }

            var result = validateFn(value, argument, scope);

            UTILS.updateExtendedReporting(result.isValid, ctrl, form, name, result);

            return result.isValid;
        };

        /**
         * Run the validation function async and update the model and form state
         * if there are issues.
         *
         * @private
         * @method runAsync
         * @param  {PromiseProvider}      $q from angular since we don't have an injector here, the
         *                                caller needs to do the injection.  Note: the createDirective()
         *                                style of invocation takes care of this for you. If calling the manually,
         *                                you need to inject $q into your directive/controller and pass it.
         * @param  {String} name          Name of the validator
         * @param  {ModelController} ctrl Model controller where we participate in normal validation status stuff
         * @param  {FormController} form  Form controller where extended error details are registered per validator.
         * @param  {Function} validateFn  Function to valid the value. Only called if value is not empty.
         * @param  {Any} value            Value to validate.
         * @param  {Any} [argument]       Optional argument to the validation function.
         * @param  {Scope} [scope]        The directive scope. Helpful if you want to $eval the argument.
         * @return {Promise}
         */
        var runAsync = function($q, name, ctrl, form, validateAsyncFn, value, argument, scope) {
            var defer = $q.defer();
            if (!ctrl.$isEmpty(value)) {
                validateAsyncFn(value, argument, scope).then(
                    function(result) {
                        UTILS.updateExtendedReporting(result.isValid, ctrl, form, name, result);
                        ctrl.$setValidity(name, result.isValid);
                        if (result.isValid) {
                            defer.resolve();
                        } else {
                            defer.reject();
                        }
                    },
                    function(error) {
                        defer.reject(error);
                    });
            }

            return defer.promise;
        };

        /**
         * Generate a directive dynamically for the specified
         * validator configuration and name.
         *
         * @private
         * @method createDirective
         * @param  {String} validationKey    [description]
         * @param  {Object} validationObject [description]
         */
        var createDirective = function(validationKey, validationObject, $q) {
            module.compileProvider.directive(validationKey, function() {
                var directiveName = validationKey;

                return {
                    require: "ngModel",
                    link: function(scope, elem, attr, ctrl) {
                        var form = elem.controller("form");
                        UTILS.initializeExtendedReporting(ctrl, form);

                        ctrl.$validators[directiveName] = function(value) {
                            var argument = attr[directiveName];
                            var fn = validationObject[directiveName];
                            var isAsync = fn.async;
                            if (!isAsync) {
                                return run(directiveName, ctrl, form, fn, value, argument, scope);
                            } else {
                                return runAsync($q, directiveName, ctrl, form, fn, value, argument, scope);
                            }
                        };

                        scope.$watch(
                            function()       {
                                return attr[directiveName];
                            },
                            function(newVal) {
                                ctrl.$validate();
                            }
                        );
                    }
                };
            });
        };

        /**
         * Creates directives based on the configuration object passed.
         *
         * @method generate
         * @param  {Object} validationObject Collection of key/function pairs for each directive to generate where:
         *    @param {String}   Name of the validator directive.
         *    @param {Function} Implementation of the validator directive validation method with the signature:
         *        fn(value, args...) where the arguments list is as follows:
         *        @param {String} value Value to validate.
         *        @param {Any}    [arg] Optional argument with a context to the specific validator.
         *    @param {Object} [$q] Optional. Only required if creating an asynchronous validator.
         *
         * @example Creating a synchronous validator
         *
         *    var validators = {
         *        isStuff: function(value) {
         *            var result = validationUtils.initializeValidationResult();
         *            if (!/stuff/.test(value)) {
         *                 result.isValid = false;
         *                 result.add("stuff", "Not stuff");
         *             }
         *             return result;
         *        }
         *    };
         *
         *    var validatorModule = angular.module("validate");
         *    validatorModule.run(["validatorFactory",
         *       function(validatorFactory) {
         *            validatorFactory.generate(validators);
         *       }
         *    ]);
         *
         * @example Creating an async validator
         *
         *    var validatorModule = angular.module("validate");
         *    validatorModule.run(["validatorFactory", "$q"
         *       function(validatorFactory, $q) {
         *            var validators = {
         *               isAsyncStuff: function(value) {
         *                   var result = validationUtils.initializeValidationResult();
         *                   var defer = $q.defer();
         *                   var timeout = $timeout(function() {
         *                       result.isValid = false;
         *                       result.add("stuff", "Not stuff");
         *                       defer.resolve(result);
         *                   });
         *                   return defer.promise;
         *               }
         *            };
         *            validators.isAsyncStuff.async = true;
         *
         *            validatorFactory.generate(validators, $q);
         *       }
         *    ]);

         */
        var generate = function(validationObject, $q) {
            var keys = _.keys(validationObject);

            for (var i = 0, len = keys.length; i < len; i++) {
                var name = keys[i];
                createDirective(name, validationObject, $q);
            }
        };

        /**
         * Construct the factory method
         *
         * @private
         * @method validate
         * @return {Object}
         *         {Function} generate Factory method to generate validation directives from configuration.
         */
        var validate = function() {
            return {
                generate: generate,
            };
        };

        module.factory("validatorFactory", validate);

        return {
            run: run,
            runAsync: runAsync,
        };
    }
);
