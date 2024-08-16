/*
# length-validators.js                            Copyright(c) 2020 cPanel, L.L.C.
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
 * This module has a collection of length validators
 *
 * @module length-validators
 * @requires angular, lodash, validator-utils, validate, locale
 */

define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/util/string",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, _, UTILS, LOCALE, STRING) {
    "use strict";

    var validators = {

        /**
             * Validates the length of the text
             *
             * @method length
             * @param {String} val Text to validate
             * @param {Number} length required length
             * @return {Object} Validation result
             */
        length: function(val, length) {
            var result = UTILS.initializeValidationResult();

            if (val.length !== length) {
                result.isValid = false;
                result.add("length", LOCALE.maketext("The length of the string should be [quant,_1,character,characters,zero].", length));
                return result;
            }

            return result;
        },

        /**
             * Validates if the length of the text does not exceed a certain length
             * @method maxLength
             * @param {String} val Text to validate
             * @param {Number} maxLength The maximum length of the input value
             * @return {Object} Validation result
             */
        maxLength: function(val, maxLength) {
            var result = UTILS.initializeValidationResult();

            if (val.length > maxLength) {
                result.isValid = false;
                result.add("maxLength", LOCALE.maketext("The length of the string cannot be greater than [quant,_1,character,characters].", maxLength));
                return result;
            }

            return result;
        },

        maxUTF8Length: function(val, maxLength) {

            // Give the simplest error message possible.
            // Any string whose UCS-2 character count exceeds maxLength
            // will always exceed the UTF-8 byte limit as well.
            // In that case let’s use the simpler error message.
            //
            if (val.length > maxLength) {
                return validators.maxLength(val, maxLength);
            }

            // We’re not out of the woods yet. If I have, e.g., 200 “é”
            // characters, that’s 400 bytes of UTF-8, which we need
            // to reject. Unfortunately more technical lingo is necessary
            // to describe this problem. :(

            var result = UTILS.initializeValidationResult();

            if (STRING.getUTF8ByteCount(val) > maxLength) {
                result.isValid = false;

                // We got here because even though val.length is under
                // our numeric limit, the actual UTF-8 byte count
                // exceeds that limit. This is a tricky thing to explain
                // concisely in non-technical terms.

                result.add("maxUTF8Length", LOCALE.maketext("This string is too long or complex. Shorten it, or replace complex (non-[asis,ASCII]) characters with simple ([asis,ASCII]) ones. (The string’s [asis,UTF-8] encoding cannot exceed [quant,_1,byte,bytes].)", maxLength));
            }

            return result;
        },

        /**
             * Validates if the input has a minimum length
             *
             * @method minLength
             * @param {String} val Text to validate
             * @param {Number} minLength The minimum length of the input value
             * @return {Object} Validation result
             */
        minLength: function(val, minLength) {
            var result = UTILS.initializeValidationResult();

            if (val.length < minLength) {
                result.isValid = false;
                result.add("minLength", LOCALE.maketext("The length of the string cannot be less than [quant,_1,character,characters].", minLength));
                return result;
            }

            return result;
        },

        /**
             * Validates if the minimum number of items are selected
             *
             * @method minSelect
             * @param {String} val Text to validate
             * @param {Number} minSelections The minimum number of selections needed
             * @return {Object} Validation result
             */
        minSelect: function(val, minSelections) {
            var result = UTILS.initializeValidationResult(),
                selected;

            if (val !== null && _.isArray(val)) {
                selected = val.length;
            }

            if (selected < minSelections) {
                result.isValid = false;
                result.add("minSelect", LOCALE.maketext("Select at least [quant,_1,item,items] from the list.", minSelections));
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
        },
    ]);

    return {
        methods: validators,
        name: "length-validators",
        description: "Validation library for length measurement of strings.",
        version: 2.0,
    };
});
