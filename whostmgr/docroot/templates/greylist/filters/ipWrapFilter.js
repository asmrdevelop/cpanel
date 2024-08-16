/*
# templates/greylist/filters/ipWrapFilter.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ], function(angular) {

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

            // Some primitive wrappers override Object.prototype.valueOf,
            var val = angular.isObject(valHolder) && // so this makes the next comparison more accurate and doubles as a guard.
                valHolder.valueOf !== Object.prototype.valueOf && // We need to make sure it's not just the inherited valueOf method.
                angular.isFunction(valHolder.valueOf);

            return val ? valHolder.valueOf() : void 0;
        }

        var app = angular.module("App");

        /**
         * Filter that separates long ipv4 and ipv6 addresses with wbr tags.
         * Also, supports separating ipv4 and ipv6 address ranges.
         * By default uses the br tag, but can use the wbr tag if a boolean true is passed in.
         *
         * @example
         *
         * Default:
         * Input => <div>{{ "0000:0000:0000:0000:0000:0000:0000:0001" | ipWrap }}</div>
         * Output => 0000:0000:0000:0000:<br>0000:0000:0000:0001
         *
         * With option set to true:
         * Input => <div>{{ "0000:0000:0000:0000:0000:0000:0000:0001" | ipWrap:true }}</div>
         * Output => 0000:0000:0000:0000:<wbr><span class="wbr"></span>0000:0000:0000:0001
         *
         */
        app.filter("ipWrap", ["$sce", function($sce) {

            var ipV6 = /^(([\da-fA-F]{1,4}:){4})(([\da-fA-F]{1,4}:){3})([\da-fA-F]{1,4})$/;
            var ipV4Range = /^((\d{1,3}.){3}\d{1,3})-((\d{1,3}.){3}\d{1,3})$/;
            var ipRangeTest = /-/;
            var ipV6Test = /:/;
            var template = "<wbr><span class=\"wbr\"></span>";

            var ipWrapper = function(value, usewbr) {

                // If it's not a string, we'll try and fetch the trusted value
                if (typeof value !== "string") {
                    value = _getTrustedValue(value);
                }

                // If value is still falsy at this point it's time to give up
                if (!value) {
                    return "";
                }

                // initialize the separator
                var separator = (usewbr) ? template : "<br>";

                // ipv6?
                if (ipV6Test.test(value)) {

                    // is this a range?
                    if (ipRangeTest.test(value)) {

                        // format the ipv6 addresses in range format
                        var ipv6Addresses = value.split(ipRangeTest);
                        var ipv6AddressRange = "";

                        // get the first part of the range
                        var match = ipV6.exec(ipv6Addresses[0]);
                        if (match) {
                            ipv6AddressRange += match[1] + separator + match[3] + match[5];
                        }

                        // add the range separator
                        ipv6AddressRange += "-" + separator;

                        // get the second part of the range
                        match = ipV6.exec(ipv6Addresses[1]);
                        if (match) {
                            ipv6AddressRange += match[1] + separator + match[3] + match[5];
                        }

                        // if all we have is -separator, then forget it
                        if (ipv6AddressRange.length > 5) {
                            return $sce.trustAsHtml(ipv6AddressRange);
                        }
                    } else {

                        // format the ipv6 address
                        var v6match = ipV6.exec(value);
                        if (v6match) {
                            return $sce.trustAsHtml(v6match[1] + separator + v6match[3] + v6match[5]);
                        }
                    }
                } else {

                    // format the ipv4 range
                    var v4rangeMatch = ipV4Range.exec(value);
                    if (v4rangeMatch) {
                        return $sce.trustAsHtml(v4rangeMatch[1] + "-" + separator + v4rangeMatch[3]);
                    }
                }

                // could not format it, just return it
                return $sce.trustAsHtml(value);
            };

            return ipWrapper;
        }
        ]);
    }
);
