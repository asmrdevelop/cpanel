/*
# sql-data-validators.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

// TODO: Add tests for these

/**
 * This module is a collection of sql validators
 *
 * @module sql-data-validators
 * @requires angular, lodash, validator-utils, validate, locale
 */
define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, validationUtils, validate, LOCALE) {

    var sqlValidators = {

        /**
             * Validates if the input is alpha numeric and
             * can have underscore and hyphen
             *
             * @method sqlAlphaNumeric
             * @param {String} val Text to validate
             * @return {Object} Validation result
             */
        sqlAlphaNumeric: function(val) {

            var result = validationUtils.initializeValidationResult();
            var regExp = /^[a-zA-Z0-9_-]+$/;

            // string cannot be empty
            if (val !== "") {

                // string cannot contain a trailing underscore
                if ((/_$/.test(val)) !== true) {

                    if (regExp.test(val) === true) {
                        result.isValid = false;
                        result.messages["regexRule"] = "The sql name should only contain alpha numeric _ and -";
                        return result;
                    }
                } else {
                    result.isValid = false;
                    result.messages["trailingUnderscore"] = "The sql name can not contain a trailing underscore";
                    return result;
                }
            } else {
                result.isValid = false;
                result.messages["notEmpty"] = "The sql name can not be empty";
                return result;
            }

            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(sqlValidators);
        }
    ]);

});
