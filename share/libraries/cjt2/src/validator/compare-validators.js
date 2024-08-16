/*
# compare-validators.js                           Copyright(c) 2020 cPanel, L.L.C.
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
 * This module has a collection of compare validators
 *
 * @module compare-validators
 * @requires angular, lodash, validator-utils, validate, locale
 */
define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, UTILS, LOCALE) {

    var IS_FRACTION_REGEXP = /\.([0-9]+)$/;

    var MATCH_WHITESPACE_REGEX = /^[^\s]+$/;

    var precheckArgumentsAreNumbers = function(result, value, valueToCompare) {
        var val    = parseFloat(value);
        if (isNaN(val)) {
            result.isValid = false;
            result.messages["default"] = LOCALE.maketext("The entered value, [_1], is not a number.", value);
            return;
        }

        var valCmp = parseFloat(valueToCompare);
        if (isNaN(valCmp)) {
            result.isValid = false;
            result.messages["default"] = LOCALE.maketext("The compare-to value, [_1], is not a number.", valueToCompare);
            return;
        }

        return {
            val: val,
            valCmp: valCmp
        };
    };

    var validators = {

        /**
             * Validates the input is equal the specified string
             *
             * @method stringEqual
             * @param {String} val Text to validate
             * @param {String} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        stringEqual: function(value, valueToCompare) {

            var result = UTILS.initializeValidationResult();

            if (typeof (value) === "string" && value !== valueToCompare) {
                result.isValid = false;
                result.add("stringEqual", LOCALE.maketext("The text you have entered is not equal to “[_1]”.", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates the input is equal the specified string (ignoring case)
             *
             * @method stringEqualIgnoreCase
             * @param {String} val Text to validate
             * @param {String} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        stringEqualIgnoreCase: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();

            if (typeof (value) === "string" && value.toLowerCase() !== valueToCompare.toLowerCase()) {
                result.isValid = false;
                result.add("stringEqualIgnoreCase", LOCALE.maketext("The text you have entered is not equal to “[_1]”.", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates the input is equal the specified number
             *
             * @method numEqual
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numEqual: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;

            if (val !== valCmp) {
                result.isValid = false;
                result.add("numEqual", LOCALE.maketext("The number you have entered is not equal to [numf,_1].", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates the input is less than a specified number
             *
             * @method numLessThan
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numLessThan: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;
            if (val >= valCmp) {

                result.isValid = false;
                result.add("numLessThan", LOCALE.maketext("The number should be less than [numf,_1].", valueToCompare));

                return result;
            }

            return result;
        },

        /**
             * Validates the input is less than or equal to a specified number
             *
             * @method numLessThanEqual
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numLessThanEqual: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;

            if (val > valCmp) {
                result.isValid = false;
                result.add("numLessThanEqual", LOCALE.maketext("The number should be less than or equal to [numf,_1].", valueToCompare));

                return result;
            }

            return result;
        },

        /**
             * Validates the input is greater than a specified number
             *
             * @method numGreaterThan
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numGreaterThan: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;
            if (val <= valCmp) {
                result.isValid = false;
                result.add("numGreaterThan", LOCALE.maketext("The number should be greater than [numf,_1].", valueToCompare));

                return result;
            }

            return result;
        },

        /**
             * Validates the input is greater than or equal to a specified number
             *
             * @method numGreaterThanEqual
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numGreaterThanEqual: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;
            if (val < valCmp) {
                result.isValid = false;

                result.add("numGreaterThanEqual", LOCALE.maketext("The number should be greater than or equal to [numf,_1].", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates that the input is a multiple of the given value
             *
             * @method numIsMultipleOf
             * @param {String} val Text to validate
             * @param {Number} valueToCompare Value to compare against
             * @return {Object} Validation result
             */
        numIsMultipleOf: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var valStr = "" + args.val;
            var valCmpStr = "" + args.valCmp;

            if (!IS_FRACTION_REGEXP.test(valStr)) {
                valStr += ".0";
            }
            if (!IS_FRACTION_REGEXP.test(valCmpStr)) {
                valCmpStr += ".0";
            }

            var valMatch = valStr.match(IS_FRACTION_REGEXP);
            var valCmpMatch = valCmpStr.match(IS_FRACTION_REGEXP);

            // To use the modulo (%) operator, both operands
            // need to be integers, which means we need to
            // shift the decimal place to the right until
            // that’s true. First, find out how many decimal
            // places we have to work with.
            var digits_to_shift = Math.max(
                valMatch[1].length,
                valCmpMatch[1].length
            );

            for (var d = 0; d < digits_to_shift; d++) {
                valStr += "0";
                valCmpStr += "0";
            }

            // Now we do the actual bit shifting.
            var replace_regexp = new RegExp("\\.([0-9]{" + digits_to_shift + "})");
            valStr = valStr.replace(replace_regexp, "$1.");
            valCmpStr = valCmpStr.replace(replace_regexp, "$1.");

            if (parseInt(valStr, 10) % parseInt(valCmpStr, 10)) {
                result.isValid = false;

                result.add("numMultipleOf", LOCALE.maketext("The number must be an even multiple of [numf,_1].", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates if the input contains certain invalid characters
             *
             * @method excludeCharacters
             * @param {String} val Text to validate
             * @param {String} valueToCompare Characters to compare
             * @return {Object} Validation result
             */
        excludeCharacters: function(value, chars) {
            var result = UTILS.initializeValidationResult(),
                excludeChars;

            if (chars !== null) {

                // convert chars into an array if it is not
                if (_.isString(chars)) {
                    excludeChars = chars.split("");
                } else {
                    excludeChars = chars;
                }

                var found = [];
                for (var i = 0, len = excludeChars.length; i < len; i++) {
                    var chr = excludeChars[i];
                    if (value.indexOf(chr) !== -1) {
                        found.push(chr);
                    }
                }

                if (found.length > 0) {
                    result.isValid = false;
                    result.add("excludeCharacters", LOCALE.maketext("The value contains the following excluded characters, which are not allowed: [_1]", found.join()));
                }
            }

            return result;
        },

        /**
             * Ensures the input contains no spaces
             *
             * @method noSpaces
             * @param {String} val Text to validate
             * @return {Object} Validation result
             */
        noSpaces: function(value) {
            var result = UTILS.initializeValidationResult();
            if (!value || value === "") {
                return result;
            }

            result.isValid = MATCH_WHITESPACE_REGEX.test(value);
            if (!result.isValid) {
                result.add("noSpaces", LOCALE.maketext("The value contains spaces."));
            }

            return result;
        },

        /**
             * Validates if the input is not equal to a specified string
             *
             * @method stringNotEqual
             * @param {String} val Text to validate
             * @param {String} valToCompare Text to compare against
             * @return {Object} Validation result
             */
        stringNotEqual: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();

            if (value === valueToCompare) {
                result.isValid = false;
                result.add("stringNotEqual", LOCALE.maketext("The text you have entered can not be equal to “[_1]”.", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates if the input is not equal to a specified string (ignore case)
             *
             * @method stringNotEqualIgnoreCase
             * @param {String} val Text to validate
             * @param {String} valToCompare Text to compare against
             * @return {Object} Validation result
             */
        stringNotEqualIgnoreCase: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();

            // ISSUE: Won't work with localization like turkish
            if (value.toLowerCase() === valueToCompare.toLowerCase()) {
                result.isValid = false;
                result.add("stringNotEqualIgnoreCase", LOCALE.maketext("The text that you entered cannot be equal to “[_1]”.", valueToCompare));
                return result;
            }

            return result;
        },

        /**
             * Validates if the input is not equal to a specified number
             *
             * @method numNotEqual
             * @param {String} val Text to validate
             * @param {Number} valToCompare Number to compare against
             * @return {Object} Validation result
             */
        numNotEqual: function(value, valueToCompare) {
            var result = UTILS.initializeValidationResult();
            var args = precheckArgumentsAreNumbers(result, value, valueToCompare);
            if (!args) {
                return result;
            }

            var val    = args.val;
            var valCmp = args.valCmp;
            if (val === valCmp) {

                result.isValid = false;
                result.add("numNotEqual", LOCALE.maketext("The number you have entered can not be equal to [numf,_1].", valueToCompare));
                return result;
            }

            return result;
        },
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
        name: "compare-validators",
        description: "Validation library for comparison of values.",
        version: 2.0,
    };
});
