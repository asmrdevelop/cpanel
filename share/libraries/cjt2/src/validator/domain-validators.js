/*
# domain-validators.js                            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false                */
/* --------------------------*/

/**
 * This module has a collection of domain validators
 *
 * @module domain-validators
 * @requires angular, validator-utils, validate, locale
 */

define([
    "lodash",
    "angular",
    "punycode",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/util/string",
    "cjt/validator/ip-validators",
    "cjt/util/idn",
    "cjt/validator/validateDirectiveFactory",
],
function(_, angular, PUNYCODE, UTILS, LOCALE, STRING, IP_VALIDATORS, IDN) {
    "use strict";

    // IMPORTANT!!! You MUST pair use of these regexps with
    // a check for disallowed characters. (cf. IDN)
    var LABEL_REGEX_IDN = /^[a-zA-Z0-9\u0080-\uffff]([a-zA-Z0-9\u0080-\uffff-]*[a-zA-Z0-9\u0080-\uffff])?$/;

    // Hostname labels are a subset of DNS labels. They may not include underscores. Interior hyphens are the only allowed special char.
    var HOSTNAME_LABEL_REGEX = /^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$/; // Same as the 'label' regex in Cpanel::Validate::Domain::Tiny

    // DNS labels may include underscores for DKIM and service records. Other special chars are not in common use.
    var DNS_LABEL_REGEX = /^[\w]([\w-]*[\w])?$/;

    var VALID_TLD_REGEX = /^[.][a-zA-Z0-9]+$/;
    var VALID_IDN_TLD_REGEX = /^[.]xn--[a-zA-Z0-9-]+$/;
    var URI_SPLITTER_REGEX = /(?:([^:/?#]+):)?(?:\/\/([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?/;
    var PORT_REGEX = /:(\d+)$/;
    var ILLEGAL_URI_CHARS_REGEX = /[^a-z0-9:/?#[\]@!$&'()*+,;=._~%-]/i;
    var INVALID_CHAR_ESCAPE = /%[^0-9a-f]/i;
    var INCOMPLETE_CHAR_ESCAPE = /%[0-9a-f](:?[^0-9a-f]|$)/i;

    var MAX_DOMAIN_BYTES = 254;
    var MAX_LABEL_BYTES = 63;

    /**
     * Tests Punycoded entry does not exceed DNS octet limit
     *
     * @private
     * @param {string} str - string to validate
     * @param {object} result - validation result object to which validation errors will be added
     * @return {boolean} validation result
     */
    function _checkLength(input, result) {

        // if entry does not include the trailing dot, add it
        if (input && input.charAt(input.length - 1) !== ".") {
            input = input + ".";
        }

        // check the maximum domain name length
        if (input.length > MAX_DOMAIN_BYTES) {
            result.addError("length", LOCALE.maketext("The domain or record name cannot exceed [quant,_1,character,characters].", MAX_DOMAIN_BYTES));
            return false;
        }

        var punycoded = PUNYCODE.toASCII(input);
        if (punycoded.length > MAX_DOMAIN_BYTES) {
            var multiBytes = STRING.getNonASCII(input);

            result.addError("length", LOCALE.maketext("The [asis,Punycode] representation of this domain or record name cannot exceed [quant,_1,character,characters]. (Non-[asis,ASCII] characters, like “[_2]”, require multiple characters to represent in [asis,Punycode].)", MAX_DOMAIN_BYTES, multiBytes[0]));

            return false;
        }

        return true;
    }

    /**
     * Tests entry includes at least 2 labels
     *
     * @private
     * @param {array} groups - array of labels to validate
     * @param {object} result - validation result object to which validation errors will be added
     * @return {boolean} validation result
     */
    function _checkTwoLabels(groups, result) {
        if (groups.length < 2) {
            result.addError("labels", LOCALE.maketext("The domain name must include at least two labels."));
            return false;
        }

        return true;
    }

    /**
     * Validate DNS label meets min and max length requirements when Punycoded
     *
     * @private
     * @param {string} str - label to validate
     * @param {object} result - validation result object to which validation errors will be added
     * @return {boolean} validation result
     */
    function _checkLabelLength(str, result) {
        if (str.length === 0) {
            result.addError("labelLength", LOCALE.maketext("A [asis,DNS] label must not be empty."));
            return false;
        }

        if (str.length > MAX_LABEL_BYTES) {
            result.addError("labelLength", LOCALE.maketext("A [asis,DNS] label must not exceed [quant,_1,character,characters].", MAX_LABEL_BYTES));
            return false;
        }

        if (PUNYCODE.toASCII(str).length > MAX_LABEL_BYTES) {
            var multiBytes = STRING.getNonASCII(str);
            result.addError("labelLength", LOCALE.maketext("The [asis,DNS] label’s [asis,Punycode] representation cannot exceed [quant,_1,byte,bytes]. (Non-[asis,ASCII] characters, like “[_2]”, require multiple characters to represent in [asis,Punycode].)", MAX_LABEL_BYTES, multiBytes[0]));
            return false;
        }

        return true;
    }

    /**
     * Validates that a string is not an IPV4 or IPV6 address
     *
     * @private
     * @param {string} str - string to validate
     * @param {object} result - validation result object to which validation errors will be added
     * @return {boolean} validation result
     */
    function _checkNotIP(str, result) {
        var isIPV4 = IP_VALIDATORS.methods.ipv4(str).isValid;
        var isIPV6 = IP_VALIDATORS.methods.ipv6(str).isValid;
        if (isIPV4 || isIPV6) {
            result.isValid = false;
            result.add("ip", LOCALE.maketext("The domain or record name cannot be [asis,IPv4] or [asis,IPv6]."));
            return false;
        }
        return true;
    }

    /**
     * Tests validity of DNS label
     * DNS labels, a superset of hostname labels, may include underscores
     *
     * @private
     * @param {string} str - label to validate
     * @param {object} result - validation result object to which validation errors will be added
     * @return {boolean} validation result
     */
    function _checkValidDNSLabel(str, result) {
        var validLabel = DNS_LABEL_REGEX.test(str);
        if (!validLabel) {
            result.isValid = false;
            result.add("dnsLabel", LOCALE.maketext("The [asis,DNS] label must contain only the following characters: [list_and,_1].", ["a-z", "A-Z", "0-9", "-", "_"]));
            return false;
        }
        return true;
    }

    /**
     * If a string ends in a period, this function removes that trailing period
     *
     * @private
     * @param {string} str - string to convert
     * @return {string} string with trailing period removed
     */
    function _removeTrailingPeriod(str) {
        if (str && str.charAt(str.length - 1) === ".") {
            str = str.slice(0, -1);
        }
        return str;
    }

    var validators = {

        /**
             * Validate fully-qualified domain name, with or without
             * a leading “*.”. IDNs are accepted and minimally validated.
             *
             * @method wildcardFqdnAllowTld
             * @param {string} input Domain name
             * @return {object} validation result
             */
        wildcardFqdnAllowTld: function wildcardFqdnAllowTld(input) {
            var result = UTILS.initializeValidationResult();

            if (!input.length) {
                result.addError("empty", LOCALE.maketext("You must enter a domain name."));
            } else if (input[0] === ".") {
                result.addError("form", LOCALE.maketext("A domain name cannot begin with “[_1]”.", "."));
            } else if (input[ input.length - 1 ] === ".") {
                result.addError("form", LOCALE.maketext("A domain name cannot end with “[_1]”.", "."));
            } else if (/\.\./.test(input)) {
                result.addError("form", LOCALE.maketext("A domain name cannot contain two consecutive dots."));
            } else if (/^[0-9.]+$/.test(input)) {
                result.addError("form", LOCALE.maketext("A domain name cannot contain only numerals."));

            // check the maximum domain name length
            } else if (_checkLength(input, result)) {
                var groups = input.split(".");

                if (_checkTwoLabels(groups, result)) {
                    var tested = {};

                    groups.forEach( function(s, i) {
                        if (s === "*") {
                            if (i !== 0) {
                                result.addError("form", LOCALE.maketext("“[_1]” can appear only at the start of a wildcard domain name.", "*"));
                            }
                        } else if ( !tested[s] ) {
                            _labelAllowIdn(s, result);
                        }

                        tested[s] = true;
                    } );
                }
            }

            return result;
        },

        /**
             * Validate fully qualified (non-IDN) domain name
             *
             * @method  fqdn
             * @param {string} fqDomain Domain name
             * @return {object} validation result
             */
        fqdn: function(fqDomain) {
            var result = UTILS.initializeValidationResult();

            var groups = fqDomain.split(".");
            var tldPart;

            // check the domain and tlds
            // must have at least one domain and tld
            if (groups.length < 2) {
                result.isValid = false;
                result.add("oneDomain", LOCALE.maketext("The domain name must include at least two labels."));
                return result;
            }

            // check the maximum domain name length
            if (!_checkLength(fqDomain, result)) {
                return result;
            }

            // check the first group for a valid domain
            result = _label(groups[0]);
            if (!result.isValid) {
                return result;
            }

            // check the last group for a valid tld
            tldPart = "." + groups[groups.length - 1];
            result = _tld(tldPart);
            if (!result.isValid) {
                return result;
            }

            // check the remaining groups
            for (var i = 1, length = groups.length - 1; i < length; i++) {

                // every part in between must start with a letter/digit
                // and end with letter/digits.
                // You can have '-' in these parts, but
                // only if they occur in between such characters.
                result = _label(groups[i]);
                if (!result.isValid) {
                    return result;
                }
            }

            return result;
        },

        /**
         * Validates that an FQDN contains at least 3 parts. Technically, you don't
         * need 3 parts for an FQDN, but at cPanel that is often what we mean. That's
         * why this validator is separate from the regular fqdn validator.
         *
         * @method threePartFqdn
         * @param  {String} fqdn   The string to validate
         * @return {Object}        The validation result
         */
        threePartFqdn: function(fqdn) {
            var result = validators.fqdn(fqdn);
            if (!result.isValid) {
                return result;
            }

            var parts = fqdn.split(".");
            if (parts.length < 3) {
                result.isValid = false;
                result.add("threeParts", LOCALE.maketext("A fully qualified domain name must contain at least 3 parts."));
            }

            return result;
        },

        /**
             * Validate fully qualified domain name, but accept wildcards
             *
             * @method  wildcardFqdn
             * @param {string} fqDomain Domain name
             * @return {object} validation result
             */
        wildcardFqdn: function(fqDomain) {
            var result = UTILS.initializeValidationResult();

            var groups = fqDomain.split(".");
            var tldPart;

            // check the domain and tlds
            // must have at least one domain and tld
            if (groups.length < 2) {
                result.isValid = false;
                result.add("oneDomain", LOCALE.maketext("The domain name must include at least two labels."));
                return result;
            }

            // check the maximum domain name length
            if (fqDomain.length > MAX_DOMAIN_BYTES ) {
                result.isValid = false;
                result.add("length", LOCALE.maketext("The domain name cannot exceed [quant,_1,character,characters].", MAX_DOMAIN_BYTES));
                return result;
            }

            // check the first group for a valid domain
            if (groups.length > 2) {

                // first can be wildcard or domain
                if (groups[0] !== "*") {

                    // first must be domain
                    result = _label(groups[0]);
                    if (!result.isValid) {
                        return result;
                    }
                }
            } else {

                // first must be domain
                result = _label(groups[0]);
                if (!result.isValid) {
                    return result;
                }
            }

            // check the last group for a valid tld
            tldPart = "." + groups[groups.length - 1];
            result = _tld(tldPart);
            if (!result.isValid) {
                return result;
            }

            // check the remaining groups
            for (var i = 1, length = groups.length - 1; i < length; i++) {

                // every part in between must start with a letter/digit
                // and end with letter/digits.
                // You can have '-' in these parts, but
                // only if they occur in between such characters.
                result = _label(groups[i]);
                if (!result.isValid) {
                    return result;
                }
            }

            return result;
        },

        /**
             * Validates a subdomain: http://<u>foo</u>.cpanel.net
             *
             * @method subdomain
             * @param  {string} str string to validate
             * @return {object} Validation result
             */
        subdomain: function(domainName) {
            var result = UTILS.initializeValidationResult();

            var groups = domainName.split(".");

            // check each group
            for (var i = 0, length = groups.length; i < length; i++) {
                var str = groups[i];

                result = _label(str);
                if (!result.isValid) {
                    return result;
                }
            }

            return result;
        },

        /**
             * Validate URL (http or https)
             *
             * @param {String} url - a string that represents a URL
             * @return {Object} validation result
             */
        url: function(str) {
            var result = UTILS.initializeValidationResult();

            if (str === null || typeof str === "undefined") {
                result.isValid = false;
                result.add("url", LOCALE.maketext("You must specify a [asis,URL]."));
                return result;
            }

            return _test_uri(str);
        },

        /**
             * Validate fully qualified domain name for addon domains
             *
             * @method  addonDomain
             * @param {string} Addon Domain name
             * @return {object} validation result
             */
        addonDomain: function(fqDomain) {
            var result = UTILS.initializeValidationResult();

            var groups = fqDomain.split(".");

            // check the domain and tlds
            // must have at least one domain and tld
            if (groups.length < 2) {
                result.isValid = false;
                result.add("domainLength", LOCALE.maketext("The domain name must include at least two labels."));
                return result;
            }

            // check each group
            for (var i = 0, length = groups.length; i < length; i++) {
                var tldPart;

                // the first entry must be a domain
                if (i === 0) {

                    // Call to subdomain() is the only difference between fqdn() and addonDomain()
                    result = this.subdomain(groups[i]);
                    if (!result.isValid) {
                        return result;
                    }
                } else if (i === groups.length - 1) { // the last entry must be a tld
                    tldPart = "." + groups[i];
                    result = _tld(tldPart);
                    if (!result.isValid) {
                        return result;
                    }
                } else {
                    result = _label(groups[i]);
                    if (!result.isValid) {
                        return result;
                    }
                }
            }

            return result;
        },

        /**
         * Validate domain name (similar to hostname, but allowing underscores)
         * Validates CNAME, DNAME, NAPTR records
         *
         * @method  domainName
         * @param {string} DNAME record
         * @return {object} validation result
         */
        domainName: function(str) {
            var result = UTILS.initializeValidationResult();
            var domainName = _removeTrailingPeriod(str);

            // If string is empty, null, or undefined, exit early with validation error
            if (!domainName) {
                result.isValid = false;
                result.add("domainName", LOCALE.maketext("You must specify a valid domain name."));
                return result;
            }

            _checkLength(domainName, result);
            _checkNotIP(domainName, result);

            var chunks = domainName.split(".");

            for (var i = 0; i < chunks.length; i++) {
                _checkLabelLength(chunks[i], result);
                _checkValidDNSLabel(chunks[i], result);
            }

            return result;
        },

        /**
         * Validate hostname input
         *
         * @method  hostname
         * @param {string} hostname value
         * @return {object} validation result
         */
        hostname: function(str) {
            var result = UTILS.initializeValidationResult();
            var hostnameToValidate = _removeTrailingPeriod(str);

            // If string is empty, null, or undefined, exit early with validation error
            if (!hostnameToValidate) {
                result.isValid = false;
                result.add("hostname", LOCALE.maketext("You must specify a valid hostname."));
                return result;
            }

            _checkLength(hostnameToValidate, result);
            _checkNotIP(hostnameToValidate, result);

            var chunks = hostnameToValidate.split(".");

            for (var i = 0; i < chunks.length; i++) {
                _label(chunks[i], result);
            }

            return result;
        },

        /**
         * Validate a redirect url
         * @method mbox
         * @param {string} mbox value
         * @return {Object} Validation result
         */
        mbox: function(str) {
            var result = UTILS.initializeValidationResult();
            var mboxToValidate = _removeTrailingPeriod(str);

            var mboxRegex = /^[a-zA-Z0-9]([a-zA-Z0-9-+#]*[a-zA-Z0-9])?$/;

            if (!mboxToValidate) {
                result.isValid = false;
                result.add("mbox", LOCALE.maketext("You must specify a valid [asis,mbox] name."));
                return result;
            }

            var chunks = mboxToValidate.split(".");

            // mbox name is an email address in domain format, with a "." in place of the "@"
            // ex - cpanemail.cpanel.net
            // for this regex, we are testing the first section of the mbox name - allowing it to contain "#" and "+" for plus addressing
            // ex - cpan+email.cpanel.net
            // ex - cpan#email.cpanel.net
            // RFC for reference - https://tools.ietf.org/html/rfc5233
            var mboxFirstChunk = mboxRegex.test(chunks[0]);

            if (!mboxFirstChunk) {
                result.isValid = false;
                result.add("mbox", LOCALE.maketext("The first [asis,mbox] label must contain only the following characters: [list_and,_1]. The label cannot begin or end with a symbol.", ["a-z", "A-Z", "0-9", "-", "+", "#"]));
            }

            for (var i = 1; i < chunks.length; i++) {
                _label(chunks[i], result);
            }

            return result;
        },

        /**
             * Validate a redirect url
             *
             * @param {String} str - a url used for redirection
             * @return {Object} Validation result
             */
        redirectUrl: function(str) {
            var result = UTILS.initializeValidationResult();

            // grab the domain and tlds
            var front_slashes = str.search(/:\/\//);
            if (front_slashes) {
                str = str.substring(front_slashes + 3);
            }

            // see if there is something after the last tld (path)
            var back_slash = str.search(/\//);
            if (back_slash === -1) {
                back_slash = str.length;
            }

            var domain_and_tld = str.substring(0, back_slash);
            if (domain_and_tld) {
                result = this.fqdn(domain_and_tld);
            }

            return result;
        },

        /**
         * Validate a DNS Zone Name
         * This method attempts to match the validation in the Whostmgr::DNS module for DNS Names.
         *
         * @method zoneName
         * @param {string} str - a zone name
         * @return {object} validation result
         */
        zoneName: function(str, type) {
            var result = UTILS.initializeValidationResult();
            var zoneNameToValidate = _removeTrailingPeriod(str);

            // If string is empty, null, or undefined, exit early with validation error
            if (!zoneNameToValidate) {
                result.isValid = false;
                result.add("zoneName", LOCALE.maketext("You must specify a valid zone name."));
                return result;
            }

            // A and AAAA records can not contain an underscore, however other records can
            if((type === "A" || type === "AAAA")) {

                var testStr = str.split(".");
                for (var i = 0, len = testStr.length; i < len; i++) {
                    if(testStr[i].includes("_")) {
                        result.isValid = false;
                        result.add("zoneName", LOCALE.maketext("An “[_1]” record may not contain an underscore. Are you trying to create a “[asis,CNAME]”?", type));
                        return result;
                    };
                };
            };

            _checkLength(zoneNameToValidate, result);

            var chunks = zoneNameToValidate.split(".");
            var firstChunkIsAnAsterisk = (chunks[0] === "*");

            var i = 0;
            if (firstChunkIsAnAsterisk) {
                i = 1;
            }

            for (var len = chunks.length; i < len; i++) {
                _checkLabelLength(chunks[i], result);
                _checkValidDNSLabel(chunks[i], result);
            }

            return result;
        },

        /**
             * Validate a DNS Zone Value that should be a FQDN, but not an IPv4 or IPv6 address
             *
             * @method zoneFqdn
             * @param {string} str - a zone record value
             * @return {object} validation result
             */
        zoneFqdn: function(str) {
            var result = UTILS.initializeValidationResult();

            if (str === null || typeof str === "undefined") {
                result.isValid = false;
                result.add("zoneFqdn", LOCALE.maketext("You must specify a fully qualified domain name."));
                return result;
            }

            // make sure it is not an ipv4 or ipv6 address
            var validIpv4 = IP_VALIDATORS.methods.ipv4(str);
            var validIpv6 = IP_VALIDATORS.methods.ipv6(str);
            if (validIpv4.isValid || validIpv6.isValid) {
                result.isValid = false;
                result.add("zoneFqdn", LOCALE.maketext("The domain cannot be [asis,IPv4] or [asis,IPv6]."));
                return result;
            }

            // finally, check if it is an fqdn
            // The last trailing dot (.) is a DNS convention to identify whether a domain is qualified or not. In UI it is optional for the user to input it. The backend will add it before saving the dns record if it is not present.
            // Ignoring it if present before validating further.
            return validators.fqdn(str.replace(/\.$/, ""));
        }

    };

        /**
         * Validates a top level domain (TLD): .com, .net, .org, .co.uk, etc
         * This function does not check against a list of TLDs.  Instead it makes sure that the TLD is formatted correctly.
         * TLD must begin with a period (.)
         * This method attempts to match the functionality of the
         * Cpanel::Validate::Domain::Tiny module.
         *
         * @method  _tld
         * @private
         * @param {string} str string to be validated
         * @return {object} validation result
         */
    // XXX: A TLD can be multiple labels, but this function only accepts
    // single-label TLDs.
    function _tld(str) {
        var result = UTILS.initializeValidationResult();

        if (!VALID_TLD_REGEX.test(str) && !VALID_IDN_TLD_REGEX.test(str)) {
            result.isValid = false;
            result.add("tld", LOCALE.maketext("The domain name must include a valid [output,acronym,TLD,Top Level Domain]."));
            return result;
        }

        return result;
    }

    function _labelBasics(str, result) {
        if (!result) {
            result = UTILS.initializeValidationResult();
        }

        // label name cannot be longer than 63 characters
        if (str.length === 0) {
            result.addError("length", LOCALE.maketext("A [asis,DNS] label must not be empty."));
        } else if (str.length > MAX_LABEL_BYTES) {
            result.addError("length", LOCALE.maketext("A [asis,DNS] label must not exceed [quant,_1,character,characters].", MAX_LABEL_BYTES));
        } else if (str[0] === "-") {
            result.addError("charCondition", LOCALE.maketext("A [asis,DNS] label must not begin with “[_1]”.", "-"));
        } else if (str[ str.length - 1 ] === "-") {
            result.addError("charCondition", LOCALE.maketext("A [asis,DNS] label must not end with “[_1]”.", "-"));
        } else if ( PUNYCODE.toASCII(str).length > MAX_LABEL_BYTES ) {
            var multiBytes = STRING.getNonASCII(str);

            result.addError("length", LOCALE.maketext("The [asis,DNS] label’s [asis,Punycode] representation cannot exceed [quant,_1,byte,bytes]. (Non-[asis,ASCII] characters, like “[_2]”, require multiple characters to represent in [asis,Punycode].)", MAX_LABEL_BYTES, multiBytes[0]));
        }

        return result;
    }

    /**
         * Validates a label: http://<u>cpanel</u>.net
         * This method attempts to match the functionality of the
         * Cpanel::Validate::Domain::Tiny module.
         *
         * @method _label
         * @private
         * @param  {string} str string to validate
         * @return {object} validation result
         */
    function _label(str, result) {
        result = _labelBasics(str, result);

        // As long as the label starts with letters/digits
        // and ends with letters/digits, you can have '-' in domain labels.
        // Also, single character domain labels are ok.
        if (!HOSTNAME_LABEL_REGEX.test(str)) {
            result.addError("labelCharCondition", LOCALE.maketext("The [asis,DNS] label must contain only the following characters: [list_and,_1].", ["a-z", "A-Z", "0-9", "-"]));
        }

        return result;
    }

    function _labelAllowIdn(str, result) {
        result = _labelBasics(str, result);

        if (LABEL_REGEX_IDN.test(str)) {

            // Only validate as an IDN if there is non-ASCII in there:
            if (/[\u0080-\uffff]/.test(str)) {
                var defects = IDN.getLabelDefects(str);

                if (defects.length) {
                    result.addError("charCondition", defects.join(" "));
                }
            }
        } else {
            result.addError("charCondition", LOCALE.maketext("The [asis,DNS] label must contain only non-[asis,ASCII] characters and the following: [list_and,_1].", ["a-z", "A-Z", "0-9", "-"]));
        }

        return result;
    }

    /**
         * Split a URI into its expected parts (scheme, authority, path)
         *
         * @private
         * @param {String} str - a URI to be split
         * @return {Array} An array of the parts of a URI
         */
    function _split_uri(str) {
        var matches = URI_SPLITTER_REGEX.exec(str);

        // throw away the first result since it will always be populated by our regex
        matches.splice(0, 1);
        return matches;
    }

    /**
         * Validate a uri using Data::Validate::URI::is_web_uri() as a reference.
         * Note that the user info component (i.e. "username@password:" portion) is not supported by this validator.
         *
         * @private
         * @param {String} str - check if this is a valid url
         * @return {object} validation result
         */
    function _test_uri(str) {
        var result = UTILS.initializeValidationResult();
        var scheme, authority, path, matches, lc_scheme, domain_valid;

        // check for illegal characters
        if (ILLEGAL_URI_CHARS_REGEX.test(str)) {
            result.isValid = false;
            result.add("url", LOCALE.maketext("A [asis,URL] must not contain illegal characters."));
            return result;
        }

        // check for hex escapes that aren't complete
        if (INVALID_CHAR_ESCAPE.test(str) || INCOMPLETE_CHAR_ESCAPE.test(str)) {
            result.isValid = false;
            result.add("url", LOCALE.maketext("A [asis,URL] must not contain invalid hexadecimal escaped characters."));
            return result;
        }

        matches = _split_uri(str);
        scheme = matches[0];
        authority = matches[1];
        path = matches[2] || ""; // normalize logic for path

        if (typeof scheme === "undefined") {
            result.isValid = false;
            result.add("url", LOCALE.maketext("A [asis,URL] must contain a valid protocol."));
            return result;
        }

        // We only check for http and https
        lc_scheme = scheme.toLowerCase();
        if (lc_scheme !== "http" && lc_scheme !== "https") {
            result.isValid = false;
            result.add("url", LOCALE.maketext("A [asis,URL] must contain a valid protocol."));
            return result;
        }

        // fully-qualified URIs must have an authority section
        if (typeof authority === "undefined" || authority.length === 0) {
            result.isValid = false;
            result.add("url", LOCALE.maketext("A [asis,URL] must contain a domain."));
            return result;
        }

        // allow a port component, but extract it since we don't need it
        authority = authority.replace(PORT_REGEX, "");

        // check for a valid domain or an IPv4 address
        // our fqdn validator allows ipv4 addresses, so no need to check for it explicitly
        domain_valid = validators.fqdn(authority);
        if (!domain_valid.isValid) {
            return domain_valid;
        }

        result.isValid = true;
        return result;
    }

    // Generate a directive for each validation function
    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "domain-validators",
        description: "Validation library for domain names.",
        version: 2.0,
    };
});
