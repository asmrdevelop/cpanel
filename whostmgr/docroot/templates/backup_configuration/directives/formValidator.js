/*
# backup_configuration/directives/formValidator.js   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/validator/validator-utils",
        "cjt/validator/domain-validators",
        "cjt/validator/path-validators",
        "cjt/validator/ip-validators",
        "cjt/validator/validateDirectiveFactory"
    ],
    function(angular, LOCALE, validationUtils, domainValidators, pathValidators, ipValidators) {
        "use strict";

        /* regular expressions used by validation checks */
        var loopbackRegex = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
        var protocolRegex = /^http(s)*:\/*/;
        var portRegex = /:\d*$/;
        var bucketRegex = /^[a-z0-9-]*$/;
        var bucketRegexAmazon = /^[a-z0-9-.]*$/;
        var bucketRegexB2 = /^[A-Za-z0-9-]*$/;
        var bucketBeginRegex = /^[-]/;
        var bucketEndRegex = /[-]$/;
        var bucketBeginRegexAmazon = /^[-.]/;
        var bucketEndRegexAmazon = /[-.]$/;
        var bucketBeginB2 = /^b2-/i;


        /* validation messages */
        var relativePathWarning = LOCALE.maketext("You must enter a relative path.");
        var subordinatePathWarning = LOCALE.maketext("You must enter a path within the user home directory.");
        var loopbackWarning = LOCALE.maketext("You cannot enter a loopback address for the remote address.");
        var noSlashesWarning = LOCALE.maketext("You must enter a value without slashes.");
        var noSpacesWarning = LOCALE.maketext("You must enter a value without spaces.");
        var noProtocolAllowedWarning = LOCALE.maketext("The remote host address must not contain a protocol.");
        var noPathWarning = LOCALE.maketext("The remote host address must not contain path information.");
        var noPortWarning = LOCALE.maketext("The remote host address must not contain a port number.");
        var absolutePathWarning = LOCALE.maketext("You must enter an absolute path.");
        var remoteHostWarning = LOCALE.maketext("The remote host address must be a valid hostname or IP address.");
        var bucketLengthWarning = LOCALE.maketext("The bucket name must be between [numf,3] and [numf,63] characters.");
        var b2BucketLengthWarning = LOCALE.maketext("The bucket name must be between [numf,6] and [numf,50] characters.");
        var bucketNameWarning = LOCALE.maketext("The bucket name must not begin or end with a hyphen.");
        var bucketNameWarningAmazon = LOCALE.maketext("The bucket name must not begin or end with a hyphen or a period.");
        var bucketAllowedCharacters = LOCALE.maketext("The bucket name must only contain numbers, hyphens, and lowercase letters.");
        var bucketAllowedCharactersAmazon = LOCALE.maketext("The bucket name must only contain numbers, periods, hyphens, and lowercase letters.");
        var bucketAllowedCharactersB2 = LOCALE.maketext("The bucket name must only contain numbers, hyphens, and letters.");
        var bucketNameB2Reserved = LOCALE.maketext("The [asis,Backblaze] [asis,B2] bucket name must not begin with “b2-” because [asis,Backblaze] reserves this prefix.");

        var validators = {

            /*
             * Checks to see if a value is a valid backup location.
             *
             * @param {string} val - form value to be evaluated
             * @param {string} arg - optional argument ("absolute") to disable relative path checking
             * @return {ValidationResult} results of the validation
             */
            backupLocation: function(val, arg) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                // allow optional field to be empty
                if (!val) {
                    result.isValid = true;
                } else if (arg !== "absolute" && val.length > 0 && val[0] === "/") {
                    result.add("backupConfigIssue", relativePathWarning);
                } else if (val.substring(0, 3) === "../") {
                    result.add("backupConfigIssue", subordinatePathWarning);
                } else {
                    result = pathValidators.methods.validPath(val);
                }

                return result;
            },

            /* Checks to see if a value is a valid S3, AmazonS3 or B2 bucket name.
             *
             * @param {string} val - form value to be evaluated
             * @param {string} arg - optional transport type ("amazon" if AmazonS3, "b2" if Backblaze b2)
             * @return {ValidationResult} results of the validation
             */
            bucket: function(val, arg) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (arg === "b2" && bucketBeginB2.test(val)) {
                    result.add("backupConfigIssue", bucketNameB2Reserved);
                } else if (arg === "b2" && !bucketRegexB2.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharactersB2);
                } else if (arg === "amazon" && !bucketRegexAmazon.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharactersAmazon);
                } else if (arg !== "amazon" && arg !== "b2" && !bucketRegex.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharacters);
                } else if (arg === "amazon" && (bucketBeginRegexAmazon.test(val) || bucketEndRegexAmazon.test(val))) {
                    result.add("backupConfigIssue", bucketNameWarningAmazon);
                } else if (arg !== "amazon" && arg !== "b2" && (bucketBeginRegex.test(val) || bucketEndRegex.test(val))) {
                    result.add("backupConfigIssue", bucketNameWarning);
                } else if (arg === "b2" && (val.length < 6 || val.length > 50)) {
                    result.add("backupConfigIssue", b2BucketLengthWarning);
                } else if (val.length < 3 || val.length > 63) {
                    result.add("backupConfigIssue", bucketLengthWarning);
                } else {
                    result.isValid = true;
                }

                return result;
            },

            /*
             * Checks to see if a value is a valid remote host or ip address.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */

            remoteHost: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                var ipCheck = ipValidators.methods.ipv4(val);

                if (ipCheck.isValid) {

                    if (loopbackRegex.test(val)) {

                        // remote destination should not be a loopback
                        result.add("backupConfigIssue", loopbackWarning);
                        return result;
                    }
                    return ipCheck;
                } else {

                    // if it's not a valid ip address
                    // check the hostname for special conditions

                    if (protocolRegex.test(val)) {
                        result.add("backupConfigIssue", noProtocolAllowedWarning);
                        return result;
                    }

                    if (val.indexOf("/") >= 0 || val.indexOf("\\") >= 0) {
                        result.add("backupConfigIssue", noPathWarning);
                        return result;
                    }

                    if (portRegex.test(val)) {
                        result.add("backupConfigIssue", noPortWarning);
                        return result;
                    }
                }

                var fqdnCheck = domainValidators.methods.fqdn(val);

                if (!ipCheck.isValid && !fqdnCheck.isValid) {
                    result.add("backupConfigIssue", remoteHostWarning);
                    return result;
                }

                return fqdnCheck;
            },

            /*
             * Checks a value for the existence of slashes.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            noslashes: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (val.indexOf("/") < 0 && val.indexOf("\\") < 0) {
                    result.isValid =  true;
                } else {
                    result.add("backupConfigIssue", noSlashesWarning);
                }

                return result;
            },

            /*
             * Checks a value for the existence of spaces.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            nospaces: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (val.indexOf(" ") < 0) {
                    result.isValid =  true;
                } else {
                    result.add("backupConfigIssue", noSpacesWarning);
                }

                return result;
            },

            /*
             * Checks a value for a valid absolute path format.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            fullPath: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = true;

                // allow optional field to be empty
                if (!val) {
                    return result;
                } else if (val.indexOf("/") !== 0) {

                    // value must start with a forward slash (/)
                    result.isValid = false;
                    result.add("backupConfigIssue", absolutePathWarning);
                } else {
                    result = pathValidators.methods.validPath(val);
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
            name: "backupConfigurationValidators",
            description: "Validation library for Backup Configuration.",
            version: 1.0,
        };
    }
);
