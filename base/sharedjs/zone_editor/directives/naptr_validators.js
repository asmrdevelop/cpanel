/*
# directives/naptr_validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
    "lodash",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, _, LOCALE, validationUtils) {

    "use strict";

    var validateServiceRegex = function(serviceValue) {
        var result = validationUtils.initializeValidationResult();

        /**
             * According to RFC - https://tools.ietf.org/html/rfc2915#section-2
             * The service field may take any of the values below(using the
             * Augmented BNF of RFC 2234[5]):
             *  service_field = [[protocol] * ("+" rs)]
             *      protocol = ALPHA * 31ALPHANUM
             *      rs = ALPHA * 31ALPHANUM
             *      ; The protocol and rs fields are limited to 32
             *      ; characters and must start with an alphabetic.
             *
             * Of note: RFC 3403 is the current specification, and it
             * does not define the above validation logic.
            **/
        // Empty value is a valid value.
        if (serviceValue === "") {
            result.isValid = true;
            return result;
        }

        var values = serviceValue.split("+");
        var protocol, rsValues;
        if (values.length > 0) {
            protocol = values.shift();
            rsValues = (values.length > 0) ? values : null;
        }

        if (!/^[a-z]/i.test(protocol)) {
            result.isValid = false;
            result.add("naptrservice", LOCALE.maketext("Service must start with a letter."));
            return result;
        }

        if (!/^[a-z][:a-z0-9\-+]{0,31}$/i.test(protocol)) {
            result.isValid = false;
            result.add("naptrservice", LOCALE.maketext("“Protocol”, the first part of the service field must contain only case insensitive letters a-z, digits 0-9, ‘-’s and ‘+’s. It must not exceed 32 characters."));
            return result;
        }

        if (rsValues) {

            var invalidRsValue = _.some(rsValues, function(rs) {
                if (rs !== "") {
                    return !(/^[:a-z0-9\-+]{1,32}$/i.test(rs));
                }
            });
            if (invalidRsValue) {
                result.isValid = false;
                result.add("naptrservice", LOCALE.maketext("Each “rs” value (the value after ‘+’ symbols) must contain only case insensitive letters a-z, digits 0-9, ‘-’s and ‘+’s. It must not exceed 32 characters."));
                result;
            }
        }

        return result;
    };

    var validateNaptrRegexField = function(naptrRegexVal) {
        var result = validationUtils.initializeValidationResult();
        if (naptrRegexVal === "") {
            return result;
        }

        // For validating the NAPTR record's ‘Regexp’ field, we used the RFC as a reference:
        // https://tools.ietf.org/html/rfc2915#page-7
        var delimCharPattern = "[^0-9i]";
        var delimCharRegex = new RegExp(delimCharPattern);
        var delimChar = naptrRegexVal.charAt(0);

        if (!delimCharRegex.test(delimChar)) {
            result.isValid = false;
            result.add("naptrRegex", LOCALE.maketext("You can not use a digit or the flag character ‘i’ as your delimiter."));
            return result;
        }

        var delimOccurrenceRegex = new RegExp("^(" + delimCharPattern + ").*\\1(.*)\\1.*");
        var matches = naptrRegexVal.match(delimOccurrenceRegex);
        if (matches === null) {
            result.isValid = false;
            result.add("naptrRegex", LOCALE.maketext("To separate regular and replacement expressions, you must enter the delimiter before, between, and after the expressions. For example, delim-char regex delim-char replacement delim-char."));
            return result;
        }
        return result;
    };

    var validators = {
        serviceValidator: function(val) {
            return validateServiceRegex(val);
        },
        naptrRegexValidator: function(val) {
            return validateNaptrRegexField(val);
        },
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        },
    ]);

    return {
        methods: validators,
        name: "naptrValidators",
        description: "Validation library for NAPTR records.",
        version: 2.0,
    };
});
