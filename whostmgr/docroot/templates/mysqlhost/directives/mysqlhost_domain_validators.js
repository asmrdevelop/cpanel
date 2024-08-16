/*
# templates/mysqlhost/directives/mysqlhost_domain_validators.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

define([
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/util/inet6",
    "cjt/validator/domain-validators",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, validationUtils, LOCALE, inet6, DOMAIN_VALIDATORS) {

    // Correlate with $Cpanel::Regex::regex{'ipv4'}
    var ipV4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;

    /**
         * Validate document root
         *
         * @method  docRootPath
         * @param {string} document root path
         * @return {object} validation result
         */
    var validators = {

        hostnameOrIp: function(val) {
            var result = validationUtils.initializeValidationResult();
            var isValid = false;

            if (_isLoopback(val)) {
                isValid = true;
            } else if (_isValidIp(val)) {
                isValid = true;
            } else {
                var output = DOMAIN_VALIDATORS.methods.fqdn(val);
                isValid = output.isValid;

                // grab messages from the other validator to this one
                if (!isValid) {
                    for (var i = 0, len = output.messages.length; i < len; i++) {
                        result.add(output.messages[i].name, output.messages[i].message);
                    }
                }
            }

            if (!isValid) {
                result.isValid = false;
                result.add("hostnameOrIp", LOCALE.maketext("The host must be a valid [asis,IP] address or [asis,hostname]."));
            }

            return result;
        },

        loopback: function(val) {
            var result = validationUtils.initializeValidationResult();

            if (_isLoopback(val)) {
                result.isValid = true;
            } else {
                result.isValid = false;
                result.add("localhost", LOCALE.maketext("The value must be a valid [asis,loopback] address."));
            }

            return result;
        }
    };

    function _isLoopback(ipOrHost) {
        switch (ipOrHost) {
            case "localhost":
            case "localhost.localdomain":
            case "0000:0000:0000:0000:0000:0000:0000:0001":
            case "0:0:0:0:0:0:0:1":
            case ":1":
            case "::1":
            case "0:0:0:0":
            case "0000:0000:0000:0000:0000:0000:0000:0000":
                return true;

            default:
                if (/^0000:0000:0000:0000:0000:ffff:7f/.test(ipOrHost) ||
                        /^::ffff:127\./.test(ipOrHost) ||
                        /^127\./.test(ipOrHost)) {
                    return true;
                }
        }

        return false;
    }

    /* hosts, domains and ip addresses */

    function _isValidIp(ipOrHost) {
        return inet6.isValid(ipOrHost) || ipV4Regex.test(ipOrHost);
    }

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "mysqlhostDomainValidators",
        description: "Validation directives for ip address and hostname.",
        version: 11.52,
    };
}
);
