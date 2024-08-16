/*
# mail_blocked_domains/services/parser.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "punycode",
        "cjt/util/locale",
        "cjt/validator/domain-validators",
        "cjt/validator/validator-utils",
    ],
    function mailBlockedDomainsParser(PUNYCODE, LOCALE, domainValidators, valUtils) {
        "use strict";

        var _validateDomain = domainValidators.methods.wildcardFqdnAllowTld;

        function _discardEmpty(a) {
            return !!a.length;
        }

        /**
        * @function parseDomainsFromText
        * @param txt String The text input to parse.
        * @returns Array The array of domains parsed from the string.
        *
        * On failure, this throws an array:
        *
        *   [
        *       [ domain1, failureReason ],
        *       [ domain2, failureReason ],
        *       ...
        *   ]
        */

        function parseDomainsFromText(txt) {
            var domains = txt.
                trim().
                split(/\s*\n\s*/).
                filter(_discardEmpty)
            ;

            var failures = [];

            var appear = {};

            domains.forEach( function(d, di) {
                var result = _validateDomain(d);

                if (result.isValid) {
                    var uvalue = PUNYCODE.toUnicode(d);

                    if (!appear[uvalue]) {
                        appear[uvalue] = 1;
                    } else {
                        if (appear[uvalue] === 1) {
                            var vresult = valUtils.initializeValidationResult();
                            vresult.addError( "duplicate", LOCALE.maketext("You may not enter any domain more than once.") );
                            failures.push( [uvalue, vresult] );
                        }

                        appear[uvalue]++;
                    }

                    domains[di] = uvalue;
                } else {
                    failures.push( [d, result] );
                }
            } );

            if (failures.length) {
                throw failures;
            }

            return domains;
        }

        return {
            parseDomainsFromText: parseDomainsFromText,
        };
    }
);
