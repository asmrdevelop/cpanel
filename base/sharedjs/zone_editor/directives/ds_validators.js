/*
# directives/ds_validators.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils) {

    "use strict";

    var digestRegex = /^[0-9a-f\s]+$/i;

    var validateDigestRegex = function(val, regex) {
        var result = validationUtils.initializeValidationResult();

        result.isValid = regex.test(val);

        if (!result.isValid) {
            result.add("digest", LOCALE.maketext("The ‘Digest‘ must be represented by a sequence of case-insensitive hexadecimal digits. Whitespace is allowed."));
        }

        return result;
    };

    var validators = {
        digestValidator: function(val) {
            return validateDigestRegex(val, digestRegex);
        }
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "digestValidators",
        description: "Validation library for DS records.",
        version: 2.0,
    };
});
