/*
# username-validators.js                          Copyright(c) 2020 cPanel, L.L.C.
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
 * This module has a collection of username validators
 *
 * @module username-validators
 * @requires angular, lodash, validator-utils, validate, locale
 */

define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, validationUtils, LOCALE) {
    "use strict";

    var FTP_USERNAME_REGEX = "[^0-9a-zA-Z_-]",
        FTP_USERNAME_MAX_LENGTH = 25;

    var usernameValidators = {

        /**
             * Validate FTP username
             *
             * @method  ftpUsername
             * @param {string} userName FTP user name
             * @return {object} validation result
             */
        ftpUsername: function(val) {
            var result = validationUtils.initializeValidationResult();

            if (typeof (val) === "string") {

                // username cannot be "FTP"
                if (val.toLowerCase() === "ftp") {
                    result.isValid = false;
                    result.add("ftpUsername", LOCALE.maketext("User name cannot be “[_1]”.", "ftp"));
                    return result;
                }

                // username cannot be longer than CPANEL.v2.app.Constants.FTP_USERNAME_MAX_LENGTH
                if (val.length > FTP_USERNAME_MAX_LENGTH) {
                    result.isValid = false;
                    result.add("ftpUsername", LOCALE.maketext("User name cannot be longer than [quant,_1,character,characters].", FTP_USERNAME_MAX_LENGTH));
                    return result;
                }

                // username must only contain these characters
                var pattern = new RegExp(FTP_USERNAME_REGEX);
                if (pattern.test(val) === true) {
                    result.isValid = false;
                    result.add("ftpUsername", LOCALE.maketext("The user name should only contain the following characters: [asis,a-zA-Z0-9-]."));
                    return result;
                }
            }

            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(usernameValidators);
        }
    ]);

    return {
        methods: usernameValidators,
        name: "username-validators",
        description: "Validation library for usernames.",
        version: 2.0,
    };

});
