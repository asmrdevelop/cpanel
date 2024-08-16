/*
# cjt/filters/htmlFilter.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular",
        "cjt/util/html",
        "ngSanitize"
    ],
    function(angular, HTML) {

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

        var module = angular.module("cjt2.filters.encodeHtml", [
            "ngSanitize"
        ]);

        /**
         * Filter that converts newline characters into <div> tags.
         *
         * @name  encodeHtml
         * @param {String} value   Value to filter.
         * @param {String} [match] Optional match pattern, defaults to \n
         * @example
         */
        module.filter("encodeHtml", [function() {
            return function(value) {

                // If it's not a string, we'll try and fetch the trusted value
                if (typeof value !== "string") {
                    value = _getTrustedValue(value);
                }

                // If value is still falsey at this point it's time to give up
                if (!value) {
                    return "";
                }

                return HTML.encode(value);
            };
        }]);

    }
);
