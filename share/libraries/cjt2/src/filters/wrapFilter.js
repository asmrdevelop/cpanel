/*
# cjt/filters/wrapFilter.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "ngSanitize"
    ],
    function(angular) {

        /**
         * Check if the object is a number
         * @note Keeping this here to keep dependencies light.

         * @private
         * @method isNumber
         * @param  {object}   obj Any object to test.
         * @return {Boolean}  true if the obj is a number, false otherwise
         */
        function isNumber(obj) {
            return !isNaN(parseFloat(obj));
        }

        /**
         * Checks if the value is a TrustedValueHolder and extracts the value if it is.
         * This is useful when something earlier in the chain returns a $secDelegate.trustAs()
         * wrapped value.
         *
         * @private
         * @method _getTrustedValue
         * @param  {Any} value          This is any var you're trying to extract a trusted value from
         * @return {String|Undefined}   If it's detected as a TrustedValueHolder, it returns the value
         */
        function _getTrustedValue(valHolder) {
            var val = angular.isObject(valHolder) &&                    // Some primitive wrappers override Object.prototype.valueOf, so this
                // makes the next comparison more accurate and doubles as a guard.
                      valHolder.valueOf !== Object.prototype.valueOf && // We need to make sure it's not just the inherited valueOf method.
                      angular.isFunction(valHolder.valueOf);

            return val ? valHolder.valueOf() : void 0;
        }

        var module = angular.module("cjt2.filters.wrap", [
            "ngSanitize"
        ]);

        /**
         * Filter that injects hidden whitespace into  strings where the match rule exists.
         * By default it does this on periods. You can provide your own regex pattern to match
         * other characters or patterns.
         *
         * @example
         *
         * Default: [Separates on period (.)]
         * <div>{{ "abc.tld" | wrap }}</div>       => <div>abc.<wbr><span class="wbr"></span>tld</div>
         *
         * With a custom regex pattern:
         * <div>{{ "ABD1:ABD2" | wrap:':' }}</div> => <div>ABD1:<wbr><span class="wbr"></span>ABD2</div>
         *
         * With a custom complex regex pattern:
         * <div>{{ "ABD1:ABD2.DDDD" | wrap:'[:.]' }}</div> => <div>ABD1:<wbr><span class="wbr"></span>ABD2.<wbr><span class="wbr"></span>DDDD</div>
         *
         * With a secondary wrap on words that exceed a max length: (note: wrapLimit must be > 2)
         *
         * <div>{{ "DDDD.01234567890123" | wrap:'[.]':10 }}</div> => <div>DDDD.<wbr><span class="wbr"></span>0123456789<wbr><span class="wbr"></span>0123</div>
         */
        module.filter("wrap", ["$sceDelegate", "$sce", function($sceDelegate, $sce) {

            var template = "<wbr><span class=\"wbr\"></span>";
            var trim = new RegExp(template + "$");
            var cache = {};

            return function(value, match, wrapLimit) {

                // If it's not a string, we'll try and fetch the trusted value
                if (typeof value !== "string") {
                    value = _getTrustedValue(value);
                }

                // If value is still falsy at this point it's time to give up
                if (!value) {
                    return "";
                }

                // Setup up defaults
                match = (!match ? "[.]" : match);
                wrapLimit = (parseInt(wrapLimit, 10) || 0);

                var ruleId = match + wrapLimit;

                // Wrap the match rule in a capture
                var expression = cache[ruleId];

                if (!expression) {

                    // The expression is not cached, so create a new cache entry for it
                    if (typeof (wrapLimit) !== "undefined" && isNumber(wrapLimit) && wrapLimit > 1) {

                        // -----------------------------------------------------------------------------------
                        // Notes:
                        // 1) We only want to take on this overhead if there is a wrapLimit
                        // 2) we use wrapLimit - 1 since the regex match the range and one more word character
                        // -----------------------------------------------------------------------------------
                        expression =  new RegExp("((?:\\w{1," + (wrapLimit - 1) + "})\\w|" + match + ")", "g");
                    } else {
                        expression =  new RegExp("(" + match + ")", "g");
                    }
                    cache[ruleId] = expression;
                }

                // Adjust the string.
                value = value.replace(expression, "$1" + template);
                if (wrapLimit) {

                    // Workaround, since the expression for limits matches at the end of the
                    // string too. I could not find an obvious way to prevent that match.
                    value = value.replace(trim, "");
                }
                return $sceDelegate.trustAs($sce.HTML, value);
            };
        }]);
    }
);
