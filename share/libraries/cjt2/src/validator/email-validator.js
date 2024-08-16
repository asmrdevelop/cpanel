/*
# email-validators.js                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false */
/* --------------------------*/

/**
 * This module has a collection of email validators
 *
 * @module email-validators
 * @requires angular, lodash, domain-validator, validator-utils, validate, locale
 */
define([
    "angular",
    "lodash",
    "cjt/validator/domain-validators",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory",
    "cjt/util/locale"
],
function(angular, _, domainValidator, validationUtils, validate, LOCALE) {
    "use strict";

    var LOCAL_MAX_LENGTH = 64;

    /**
     * Check if a given email address is a sub-address of a reserved email address.
     *
     * @param  {String}  email         Email that we are trying to figure out is a sub-account of the reserved email account passed.
     * @param  {String}  reservedEmail Reserved email
     * @return {Boolean}               true is the email address is a sub account of the reserved email address, false otherwise.
     */
    function _isSubAddressOf(email, reservedEmail) {
        if (!/[^+]+[+][^+]*@.+/.test(email)) {
            return false;
        }

        var emailParts         = email.split("@");
        var reservedEmailParts = reservedEmail.split("@");

        if (emailParts[1] !== reservedEmailParts[1]) {

            // can not be a subaddress since host is different
            return false;
        }

        if (emailParts[0] === reservedEmailParts[0]) {

            // can not be a subaddress since they are already equal
            return false;
        }

        var emailBox = emailParts[0];
        var reservedBox = reservedEmailParts[0];

        var subAddressRegEx = new RegExp("^" + reservedBox + "[+].*$");
        return subAddressRegEx.test(emailBox);
    }

    /**
     * Check if the email is in the reserved list passed.
     *
     * @param  {String}       email
     * @param  {String|Array} reservedEmails
     * @param  {Boolean}      subAddressesReserved
     * @return {Boolean}      true if the email is reserved, false if the email is not reserved.
     */
    function _isEmailReserved(email, reservedEmails, subAddressesReserved) {

        var result = validationUtils.initializeValidationResult();

        if (!/^[^@]+@.+$/.test(email)) {
            return result; // The email is not a valid email yet.
        }

        if (!angular.isDefined(subAddressesReserved)) {
            subAddressesReserved = true;
        } else {
            subAddressesReserved = !!subAddressesReserved;
        }

        if (!reservedEmails) {
            return result; // no reserved emails passed, nothing to do.
        }

        if ( angular.isString(reservedEmails)) {
            reservedEmails = [ reservedEmails ];
        }

        if (!reservedEmails.length) {
            return result; // no reserved emails passed, nothing to do.
        }

        for (var i = 0, l = reservedEmails.length; i < l; i++) {
            var reservedEmail = reservedEmails[i];
            if (!/^[^@]+@.+$/.test(reservedEmail)) {
                return result; // The reserved email is not a valid email yet.
            }

            var isReserved = email === reservedEmail;
            var isSubAddressOfReserved = subAddressesReserved && _isSubAddressOf(email, reservedEmail);
            if ( isReserved || isSubAddressOfReserved ) {

                var message;
                if (subAddressesReserved && isSubAddressOfReserved) {
                    message = LOCALE.maketext(
                        "You must use an email address that does not exist in the following list: [list_or,_1], or a [asis,subaddress] of [quant,_2,this email address, one of these email addresses].",
                        reservedEmails,
                        reservedEmails.length
                    );
                } else {
                    message = LOCALE.maketext(
                        "You must use an email address that does not exist in the following list: [list_or,_1].",
                        reservedEmails
                    );
                }

                result.addError(
                    "reservedEmail",
                    message
                );
                break; // We do not need to check on every one if one fails.
            }
        }

        return result;
    }

    var emailValidators = {

        /**
             * Validates an email address
             *
             * @method  email
             * @param  {String} val    The input value
             * @param  {String} spec   The spec to validate against (rfc or cpanel), defaults to "rfc".
             * @return {Object}        A ValidationResult object
             */
        email: function(val, spec) {
            spec = spec || "rfc";
            if (!_.includes(["cpanel", "rfc"], spec)) {
                throw new Error("Invalid spec passed to email() validator: " + spec + ".");
            }

            var result = validationUtils.initializeValidationResult();

            if (val !== "") {

                // split on the @ symbol
                var groups = val.split("@");

                // must be split into two at this point
                if (groups.length !== 2) {
                    result.addError("twoParts", LOCALE.maketext("The email must contain a username and a domain.") );
                    return result;
                }

                var localPart = groups[0],
                    domainPart = groups[1];

                result = _getUsernameResult(localPart, spec);

                if (result.isValid) {
                    var fqdn = domainValidator.methods.fqdn;
                    result = fqdn(domainPart);
                }
            }
            return result;
        },

        /**
         * Validates that the email is not in the reserved list or a sub-address
         * of any of the emails in the reserved list. Performs case insensitive
         * matches. Assumes the <box>+<subbox>@<domain> style of sub addressing.
         *
         * @method emailNotReserved
         * @param  {String} email                 The email to be created or edited
         * @param  {String|Array} reservedEmails  The alternative email.
         * @return {Object}                       A ValidationResult object
         */
        emailNotReservedIncludeSubAddresses: function(email, reservedEmails) {
            return _isEmailReserved(email, reservedEmails, true);
        },

        /**
         * Validates that the email is not in the reserved list. Performs case insensitive
         * exact matches only.
         *
         * @method emailNotReserved
         * @param  {String} email                 The email to be created or edited
         * @param  {String|Array} reservedEmails  The alternative email.
         * @return {Object}                       A ValidationResult object
         */
        emailNotReserved: function(email, reservedEmails) {
            return _isEmailReserved(email, reservedEmails, false);
        },

        /**
             * Validates the username (like the local part of an email) based on
             * cpanel or rfc rules. A username is everything before the @ sign in
             * a fully qualified username like "user2@domain.tld".
             *
             * The username in this instance should just be "user2".
             *
             * @method username
             * @param {String} username   The username to validate
             * @param {String} spec       The spec to validate against. The only
             *                            valid values are "cpanel" and "rfc". Defaults to "rfc".
             * @return {Object} result    A ValidationResult object
             */
        username: function(username, spec) {
            spec = spec || "rfc";
            if (!_.includes(["cpanel", "rfc"], spec)) {
                throw "Invalid spec passed to email() validator: " + spec + ".";
            }

            return _getUsernameResult(username, spec);
        },

    };

        /**
         * A phrase map to associate short failure strings with localized phrases.
         */
    var phrases = {
        username: {
            rfc: {
                emptyString: LOCALE.maketext("You must enter a username."),
                maxLength: LOCALE.maketext("The username cannot exceed [numf,_1] characters.", LOCAL_MAX_LENGTH),
                invalidChars: LOCALE.maketext("The username can only contain the following characters: [asis,a-zA-Z0-9!#$%][output,asis,amp()][output,apos][asis,*+/=?^_`{|}~-]"),
                atSign: LOCALE.maketext("Do not include the [asis,@] character or the domain name."),
                startEndPeriod: LOCALE.maketext("The username cannot begin or end with a period."),
                doublePeriod: LOCALE.maketext("The username cannot contain two consecutive periods.")
            },
            cpanel: {
                emptyString: LOCALE.maketext("You must enter a username."),
                maxLength: LOCALE.maketext("The username cannot exceed [numf,_1] characters.", LOCAL_MAX_LENGTH),
                invalidChars: LOCALE.maketext("The username can only contain letters, numbers, periods, hyphens, and underscores."),
                atSign: LOCALE.maketext("Do not include the [asis,@] character or the domain name."),
                startEndPeriod: LOCALE.maketext("The username cannot begin or end with a period."),
                doublePeriod: LOCALE.maketext("The username cannot contain two consecutive periods.")
            }
        }
    };

        /**
         * Performs the username validation and returns a ValidationResult object.
         * See emailValidators.username for more information on usernames.
         *
         * @method _getUsernameResult
         * @private
         * @param  {String} username   The username
         * @param  {String} spec       The spec to validate against
         * @return {Object}            A ValidationResult object
         */
    function _getUsernameResult(username, spec) {
        var failures = _validateUsername(username, spec);
        return _makeResult(failures, phrases.username[spec]);
    }

    /**
         * Transforms a list of failures into a full ValidationResult object with
         * corresponding messages added, using a phrase map. If the failure list
         * is empty, no messages are added and a valid ValidationResult is returned.
         *
         * @method _makeResult
         * @private
         * @param  {Array}  failures    A list of short failure strings
         * @param  {Object} phraseMap   An object that maps short failure strings
         *                              to localized, informative messages
         * @return {Object}             A ValidationResult object with zero, one,
         *                              or multiple messages
         */
    function _makeResult(failures, phraseMap) {
        var result = validationUtils.initializeValidationResult();

        failures.forEach(function(failureName) {
            result.addError(failureName, phraseMap[failureName]);
        });

        return result;
    }

    /**
         * Validates a username and returns a list of failures for any part of
         * the username that don't comply with the specified validation rules.
         * See emailValidators.username for more information on usernames.
         *
         * @method  _validateUsername
         * @private
         * @param  {String} username   The username
         * @param  {String} spec       The spec to validate against
         * @return {Array}             An array of short failure strings
         */
    function _validateUsername(username, spec) {

        // Initialize the parameters
        var failures = [];
        spec = spec || "rfc";

        // If it's an empty string there's no sense in checking anything else.
        // In Angular, validators don't process empty strings but leaving this
        // here for any other utilities that might use it.
        if (username === "") {
            failures.push("emptyString");
            return failures;
        }

        if (username.length > LOCAL_MAX_LENGTH) {
            failures.push("maxLength");
        }

        // Validate the inputs
        if (spec !== "cpanel" && spec !== "rfc") {
            throw ("CJT2/validator/email-validator: invalid spec argument!");
        }

        // username must contain only these characters
        var pattern;
        if (spec === "rfc") {
            pattern = new RegExp("[^.a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]");
        } else if (spec === "cpanel") {

            // This is the current set of chars allowed when creating a new cPanel sub-account
            pattern = new RegExp("[^.a-zA-Z0-9_-]");
        }

        if (pattern.test(username) === true) {
            failures.push("invalidChars");
        }

        if (username.indexOf("@") > -1) {
            failures.push("atSign");
        }

        // If the username has '.' as the first or last character then it's not valid
        if (username.charAt(0) === "." || username.charAt(username.length - 1) === ".") {
            failures.push("startEndPeriod");
        }

        // If the username contains '..' then it's not valid
        if (/\.\./.test(username) === true) {
            failures.push("doublePeriod");
        }

        return failures;
    }

    // Register the directive
    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(emailValidators);
        }
    ]);

    return {
        methods: emailValidators,
        name: "email-validators",
        description: "Validation library for email addresses.",
        version: 2.0,
    };
});
