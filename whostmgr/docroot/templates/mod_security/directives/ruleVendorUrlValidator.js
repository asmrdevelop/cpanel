/*
# ruleVendorUrlValidator.js                       Copyright(c) 2020 cPanel, L.L.C.
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
 * This module has validators for the rule vendor url format.
 *
 * @module ruleVendorUrlValidator
 * @requires angular, validator-utils, validate, locale
 */

define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/domain-validators",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, UTILS, LOCALE, DOMAIN_VALIDATORS) {

    /**
         * Expand the protocol with the colon.
         *
         * @private
         * @method _expandProtocol
         * @param  {String} value
         * @return {String}
         */
    var _expandProtocol = function(value) {
        return value + ":";
    };

    var VALID_PROTOCOLS = [ "http", "https" ];
    var VALID_PROTOCOLS_PATTERN = new RegExp("^(?:" + _.map(VALID_PROTOCOLS, _expandProtocol).join("|") + ")$", "i");
    var VALID_FILE_NAME_PATTERN = /^meta_[a-zA-Z0-9_-]+\.yaml$/;
    var VALID_FILE_PREFIX = /^meta_/;
    var VALID_FILE_EXTENSION = /\.yaml$/;

    var validators = {

        /**
             * Checks if the string is valid vendor url. To be valid, it must meet the following rules:
             *   1) It must be a valid url
             *   2) It must only use the http protocol.
             *   3) It must point to a file name with the following parts:
             *       a) Starts with meta_
             *       b) Followed by a vendor name
             *       c) With a .yaml extension.
             *
             * Obviously it must conform to other requirements such as pointing to a valid YAML file in the
             * correct format for a vendor meta data file. These final aspects are validated on the server
             * during load process, not on the client.
             * @param  {String}  value
             * @return {Object}       Returns the extended validation object to the validator.
             */
        isModsecVendorUrl: function(value) {
            var result = UTILS.initializeValidationResult();

            if (value) {

                var parts = value.split(/\//);
                var length = parts.length;
                var last = length - 1;

                // 0) Must have at least 3 forward slashes, indicating that the URL has a protocol, domain and filename
                if (length < 4) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The URL must contain a protocol, domain, and file name in the correct format. (Example: [asis,https://example.com/example/meta_example.yaml])"));
                    return result;
                }

                // 1) Part 0 should be a protocol: http:
                if (!VALID_PROTOCOLS_PATTERN.test(parts[0])) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The URL must use one of the following recognized protocols: [join,~, ,_1]", VALID_PROTOCOLS));
                    return result;
                }

                // 2) Part 1 should be empty from between the //
                //    Note: This test doesn't account for the colon directly, but the error message mentions it because it provides an easy spatial reference
                //    for the user. If we reach this test, we will have passed the protocol test and that one already includes testing for the colon.
                if (parts[1] !== "") {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The protocol should be followed by a colon and two forward slashes. (Example: [asis,https://])"));
                    return result;
                }

                // 3) Part 2 should be a domain
                var domainResults = DOMAIN_VALIDATORS.methods.fqdn(parts[2]);
                if (!domainResults.isValid) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", domainResults.messages[0].message);
                    return result;
                }

                // 4) An optional path, we are just going to ignore it.

                // 5) Part n should be a file name and is not required
                if (last < 3) {
                    result.add("isModsecVendorUrl", LOCALE.maketext("The file name must start with meta_, followed by the vendor name and have the .yaml extension. (Example: [asis,meta_example.yaml])"));
                } else {
                    var fileName = parts[last];

                    if (!VALID_FILE_NAME_PATTERN.test(fileName)) {
                        result.isValid = false;
                        var failedPrefixTest = !VALID_FILE_PREFIX.test(fileName);
                        var failedExtensionTest = !VALID_FILE_EXTENSION.test(fileName);

                        var numFailed = failedPrefixTest + failedExtensionTest; // Implicit coersion to a number

                        // If several conditions fail, give them the whole spiel, otherwise just give them their specific error.
                        if (numFailed > 1) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must use the meta_ prefix, followed by the vendor name and a .yaml extension. The vendor name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])", ["a-z", "A-Z", "0-9", "-", "_"]));
                        } else if (failedPrefixTest) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must use the meta_ prefix. (Example: [asis,meta_example.yaml])"));
                        } else if (failedExtensionTest) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must have the .yaml extension. (Example: [asis,meta_example.yaml])"));
                        } else { // By the process of elimination, the only part left of the filename that could be wrong is the vendor_id
                            result.add("isModsecVendorUrl", LOCALE.maketext("The vendor name part of the file name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])", ["a-z", "A-Z", "0-9", "-", "_"] ));
                        }

                        return result;
                    }
                }
            }
            return result;
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
        name: "ruleVendorUrlValidator",
        description: "Validation directives for rule vendor urls.",
        version: 11.48,
    };
});
