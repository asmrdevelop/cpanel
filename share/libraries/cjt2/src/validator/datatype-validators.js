/*
# datatype-validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false                */
/* --------------------------*/


/**
 * This module is a collection of data-type validators
 *
 * @module datatype-validators
 * @requires angular, validator-utils, validate, locale
 */
define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, UTILS, LOCALE) {

    "use strict";
    var DOLLAR_AMOUNT_REGEXP = /^[0-9]+(?:\.[0-9]{1,2})?$/;


    /**
     * Validates the given value to see if it is a float number with the given
     * precision value.
     *
     * @param {String} numberToValidate  The value to be validated.
     * @param {String} decimalPrecision  The precision up to which the decimal places need to be validated.
     * @param {Boolean} allowNegativeValues   Whether it should validate negative numbers or not.
     * @returns {Boolean} Validity of value true or false.
     */
    function validateFloatNumbers(numberToValidate, decimalPrecision, allowNegativeValues) {
        decimalPrecision = (_.isFinite(parseInt(decimalPrecision))) ? decimalPrecision : "";
        var allowNegativeRegex = (allowNegativeValues) ? "-?" : "";
        var precisionRegex = "{1," + decimalPrecision + "}";
        var regex = new RegExp("^" + allowNegativeRegex + "\\d+(\\.\\d" + precisionRegex + ")?$");
        return regex.test(numberToValidate);
    }

    var validators = {

        /**
         * Validates if the input is a digit
         *
         * @method digits
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        digits: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^\d+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("digits", LOCALE.maketext("The input should only contains numbers."));
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is a dollar amount.
         * Currently this does NOT accept either localized
         * numbers (e.g., '12,45' in German) or thousands separators
         * (e.g., '1,200' in English).
         *
         * @method digits
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        isDollarAmount: function(val) {
            var result = UTILS.initializeValidationResult();

            var isValid = (val !== "") && DOLLAR_AMOUNT_REGEXP.test(val);

            if (!isValid) {
                result.isValid = false;
                result.add("isDollarAmount", LOCALE.maketext("The input should contain a dollar (USD) amount."));
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is an integer
         *
         * @method integer
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        integer: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^-?\d+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("integer", LOCALE.maketext("The input should be a whole number."));
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is a positive integer
         *
         * Validates that the input is a NONNEGATIVE integer. Note that this validator is,
         * for historical reasons, misnamed; a “positive integer” validator should actually reject 0.
         * Consider using `positiveOrZeroInteger` in all new code.
         *
         * @method positiveInteger
         * @param {String} val Text to validate
         * @param {String} message optional error message to report
         * @return {Object} Validation result
         */
        positiveInteger: function(val, message) {
            var result = UTILS.initializeValidationResult();
            var msg;

            if (message) {
                msg = message;
            } else {
                msg = LOCALE.maketext("The input should be a positive whole number.");
            }

            var regExp = /^\d+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("positiveInteger", msg);
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is a positive integer or 0
         *
         * @method positiveOrZeroInteger
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        positiveOrZeroInteger: function(val) {
            var msg = LOCALE.maketext("The input should be zero or a positive whole number.");
            return validators.positiveInteger(val, msg);
        },

        /**
         * Validates if the input is a negative integer
         *
         * @method negativeInt
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        negativeInteger: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^-\d+$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("negativeInteger", LOCALE.maketext("The input should be a negative whole number."));
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is a float with the given decimal precision.
         *
         * @method float
         * @param {String} val Text to validate
         * @param {number} decimalPrecision number specifying the precision.
         * @return {Object} Validation result
         */
        float: function(val, decimalPrecision) {
            var result = UTILS.initializeValidationResult();
            var isValid = validateFloatNumbers(val, decimalPrecision, true);
            if (!isValid) {
                result.isValid = false;
                result.add("float", LOCALE.maketext("The input must be a float number with up to [quant,_1, decimal place, decimal places].", decimalPrecision));
                return result;
            }
            return result;
        },

        /**
         * Validates if input is a positive float number with the given decimal precision.
         *
         * @method positiveFloat
         * @param {String} val Text to validate
         * @param {number} decimalPrecision number specifying the precision.
         * @return {Object} Validation result
        */
        positiveFloat: function(val, decimalPrecision) {
            var result = UTILS.initializeValidationResult();
            var isValid = validateFloatNumbers(val, decimalPrecision, false);
            if (!isValid) {
                result.isValid = false;
                result.add("positiveFloat", LOCALE.maketext("The input must be a positive float number with up to [quant,_1, decimal place, decimal places].", decimalPrecision));
                return result;
            }
            return result;
        },

        /**
         * Validates if the input is a valid hex color
         *
         * @method hexColor
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        hexColor: function(val) {
            var result = UTILS.initializeValidationResult();

            var regExp = /^([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
            var isValid = val !== "" ? regExp.test(val) : false;

            if (!isValid) {
                result.isValid = false;
                result.add("hexColor", LOCALE.maketext("The input should be a valid hexadecimal color (excluding the pound sign)."));
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
        name: "datatype-validators",
        description: "Validation library for integer, digit, and similar.",
        version: 2.0,
    };

});
