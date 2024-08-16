/*
# ascii-data-validators.js                        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

/**
 * This module is a collection of data-type validators
 *
 * @module ascii-data-validators
 * @requires angular, validator-utils, validate, locale
 */
define([
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, UTILS, LOCALE) {

    var validators = {

        /**
             * Validates if the input has all alphabets
             *
             * @method alpha
             * @param {String} val Text to validate
             * @return {Object} Validation result
             */
        alpha: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^[a-zA-Z]+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("alpha", LOCALE.maketext("The value should only contain the letters [asis,a-z] and [asis,A-Z]."));
                return result;
            }

            return result;
        },

        /**
             * Validates if the input is all upper case
             *
             * @method upperCaseOnly
             * @param {String} val Text to validate
             * @return {Object} Validation result
             */
        upperCaseOnly: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^[A-Z]+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("upperCaseOnly", LOCALE.maketext("The value should only contain uppercase letters."));
                return result;
            }
            return result;
        },

        /**
             * Validates if the input is all lower case
             *
             * @method lowerCaseOnly
             * @param {String} val Text to validate
             * @return {Object} Validation result
             */
        lowerCaseOnly: function(val) {
            var result = UTILS.initializeValidationResult();
            var regExp = /^[a-z]+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("lowerCaseOnly", LOCALE.maketext("The value should only contain lowercase letters."));
                return result;
            }
            return result;
        },

        /**
             * Validates if the input is alpha numeric only
             *
             * @method alphaNumeric
             * @param {String} val Text to validate
             * @return {Object} Validation Result
             */
        alphaNumeric: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^\w+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("alphaNumeric", LOCALE.maketext("The value should only contain alphanumeric characters."));
                return result;
            }
            return result;
        },

        /**
             * Validates if the input starts with the passed in pattern.
             *
             * @method startsWith
             * @param {String} val Text to validate
             * @param {String} match Text to match
             * @return {Object} Validation Result
             */
        startsWith: function(val, match) {
            var result = UTILS.initializeValidationResult();

            var regExp = new RegExp("^" + match);
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("startsWith", LOCALE.maketext("The value should start with “[_1]”.", match));
                return result;
            }
            return result;
        },

        /**
             * Validates if the input ends with the passed in pattern.
             *
             * @method endsWith
             * @param {String} val Text to validate
             * @param {String} match Text to match
             * @return {Object} Validation Result
             */
        endsWith: function(val, match) {
            var result = UTILS.initializeValidationResult();

            var regExp = new RegExp(match + "$");
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("endsWith", LOCALE.maketext("The value should end with “[_1]”.", match));
                return result;
            }
            return result;
        }
    };

        // Generate a directive for each validation function
    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "ascii-data-validators",
        description: "Validation library for ascii values.",
        version: 2.0,
    };
});
