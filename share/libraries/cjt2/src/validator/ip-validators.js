/*
# ip-validators.js                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * This module has a collection of IP Address validators
 *
 * @module ip-validators
 * @requires angular, validator-utils, validate, locale
 */

define([
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/util/inet6",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, UTILS, LOCALE, INET6) {
    "use strict";

    var POSITIVE_INTEGER = /^\d+$/;
    var LEADING_ZEROES = /^0+[0-9]+$/;

    var validators = {

        /**
             * Validate an IPv4 Address
             *
             * @method ipv4
             * @param {string} str - A string representing an IP address
             * @return {object} validation result
             */
        ipv4: function(str) {
            var result = UTILS.initializeValidationResult();

            if (str === null || typeof str === "undefined") {
                result.isValid = false;
                result.add("ipv4", LOCALE.maketext("You must specify a valid [asis,IP] address."));
                return result;
            }

            var chunks = str.split(".");

            if (chunks.length !== 4 || chunks[0] === "0") {
                result.isValid = false;
                result.add("ipv4", LOCALE.maketext("You must specify a valid [asis,IP] address."));
                return result;
            }

            for (var i = 0; i < chunks.length; i++) {
                if (!POSITIVE_INTEGER.test(chunks[i])) {
                    result.isValid = false;
                    break;
                }

                if (chunks[i] > 255) {
                    result.isValid = false;
                    break;
                }

                // We need to account for leading zeroes, since those cause issues with BIND
                // Check for leading zeroes and error out if the value is not just a zero
                if (LEADING_ZEROES.test(chunks[i])) {
                    result.isValid = false;
                    break;
                }
            }

            if (!result.isValid) {
                result.add("ipv4", LOCALE.maketext("You must specify a valid [asis,IP] address."));
            }

            return result;
        },

        /**
             * Validate an IPv6 Address
             *
             * @method ipv6
             * @param {string} str - A string representing an IPv6 address
             * @return {object} validation result
             */
        ipv6: function(str) {
            var result = UTILS.initializeValidationResult();
            var check = INET6.isValid(str);

            if (!check) {
                result.isValid = false;
                result.add("ipv6", LOCALE.maketext("You must specify a valid [asis,IP] address."));
                return result;
            }

            return result;
        },

        /**
         * Validate an IPv4 CIDR Range
         *
         * @method cidr4
         * @param {string} str - A string representing an IPv6 address
         * @return {object} validation result
         */
        cidr4: function(str) {
            var cidr = str.split("/");
            var range = cidr[1], address = cidr[0];

            var isOctetValid = function(rule, octet, name, result) {
                if (!rule) {
                    return false;
                } else if ( !Object.prototype.hasOwnProperty.call(rule, name) ) {

                    // octent can be anything
                    return true;
                } else if (rule[name] === 0 && octet !== 0) {
                    result.add("cidr-details", LOCALE.maketext("In an [asis,IP] address like [asis,a.b.c.d], the “[_1]” octet must be the value 0 for this CIDR range.", name));

                    // octet must be 0
                    return false;
                } else if ( rule[name].length && !rule[name].includes(octet)) {
                    result.add("cidr-details", LOCALE.maketext("In an [asis,IP] address like [asis,a.b.c.d], the “[_1]” octet must be one of the values in: [list_or,_2].", name, rule[name]));

                    // octet must be one of the list
                    return false;
                } else if ( rule[name].max ) {
                    if (octet < rule[name].min || octet > rule[name].max) {
                        result.add("cidr-details", LOCALE.maketext("In an [asis,IP] address like [asis,a.b.c.d], the “[_1]” octet must be greater than or equal to “[_2]” and less than or equal to “[_3]”.", name, rule[name].min, rule[name].max));

                        // octet out of the allowed range
                        return false;
                    } else if (octet % rule[name].by !== 0) {
                        result.add("cidr-details", LOCALE.maketext("In an [asis,IP] address like [asis,a.b.c.d], the “[_1]” octet must be evenly divisible by “[_2]”.", name, rule[name].by));

                        // octet not evenly divisible
                        return false;
                    }
                }
                return true;
            };

            var result = this.ipv4(address);
            if (result.isValid) {

                // check the cidr range
                if (range) {
                    if (range < 0 || range > 32) {
                        result.isValid = false;
                        result.add("cidr", LOCALE.maketext("You must specify a valid [asis,CIDR] range between 0 and 32."));
                        return result;
                    }

                    // Precalculate the validation rules
                    // CIDR Format:
                    //
                    //   a.b.c.d/range
                    //
                    // Each record below defines the rules for a specific range
                    // For any octet slot (a,b,c,d) that underfined in the rule,
                    //  any value is allowed.
                    var rules = {
                        32: {},
                        31: { d: { min: 0, max: 254, by: 2 } },
                        30: { d: { min: 0, max: 252, by: 4 } },
                        29: { d: { min: 0, max: 248, by: 8 } },
                        28: { d: { min: 0, max: 240, by: 16 } },
                        27: { d: { min: 0, max: 224, by: 32 } },
                        26: { d: [ 0, 64, 128, 192 ] },
                        25: { d: [ 0, 128 ] },
                        24: { d: 0 },
                        23: { d: 0, c: { min: 0, max: 254, by: 2 } },
                        22: { d: 0, c: { min: 0, max: 252, by: 4 } },
                        21: { d: 0, c: { min: 0, max: 248, by: 8 } },
                        20: { d: 0, c: { min: 0, max: 240, by: 16 } },
                        19: { d: 0, c: { min: 0, max: 224, by: 32 } },
                        18: { d: 0, c: [ 0, 64, 128, 192 ] },
                        17: { d: 0, c: [ 0, 128 ] },
                        16: { d: 0, c: 0 },
                        15: { d: 0, c: 0, b: { min: 0, max: 254, by: 2 } },
                        14: { d: 0, c: 0, b: { min: 0, max: 252, by: 4 } },
                        13: { d: 0, c: 0, b: { min: 0, max: 248, by: 8 } },
                        12: { d: 0, c: 0, b: { min: 0, max: 240, by: 16 } },
                        11: { d: 0, c: 0, b: { min: 0, max: 224, by: 32 } },
                        10: { d: 0, c: 0, b: [ 0, 64, 128, 192 ] },
                        9: { d: 0, c: 0, b: [ 0, 128 ] },
                        8: { d: 0, c: 0, b: 0 },
                        7: { d: 0, c: 0, b: 0, a: { min: 0, max: 254, by: 2 } },
                        6: { d: 0, c: 0, b: 0, a: { min: 0, max: 252, by: 4 } },
                        5: { d: 0, c: 0, b: 0, a: { min: 0, max: 248, by: 8 } },
                        4: { d: 0, c: 0, b: 0, a: { min: 0, max: 240, by: 16 } },
                        3: { d: 0, c: 0, b: 0, a: { min: 0, max: 224, by: 32 } },
                        2: { d: 0, c: 0, b: 0, a: [ 0, 64, 128, 192 ] },
                        1: { d: 0, c: 0, b: 0, a: [ 0, 128 ] },
                        0: { d: 0, c: 0, b: 0, a: 0 },
                    };

                    var octets = address.split(/\./); // a.b.c.d
                    var rule = rules[range];

                    var isValid = ["a", "b", "c", "d"].reduce(function(isValid, name, index) {
                        isValid = isValid && isOctetValid(rule, Number(octets[index]), name, result);
                        return isValid;
                    }, true);

                    if (!isValid) {
                        result.isValid = false;
                        result.add("cidr", LOCALE.maketext("The [asis,IP] address, [_1], in the [asis,CIDR] range is not supported for the range /[_2].", address, range));
                    }
                } else {
                    result.isValid = false;
                    result.add("cidr", LOCALE.maketext("The [asis,CIDR] range must include a ‘/’ followed by the range."));
                }
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
        name: "ip-validators",
        description: "Validation library for IP Addresses.",
        version: 2.0,
    };
});
