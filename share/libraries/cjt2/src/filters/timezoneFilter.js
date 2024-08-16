/*
# cjt/filters/timezoneFilter.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/string"
    ],
    function(angular, STRING) {
        "use strict";

        var module = angular.module("cjt2.filters.timezone", []);

        /**
         * Filter that converts a timezone in minutes to a timezone in +/- hour:min.
         *
         * @example
         *
         * {{ -300 | timezone }} => -5:00
         * {{ 0 | timezone }} => 0:00
         * {{ 0 | timezone: false }} => Z
         * {{ 300 | timezone }} => +5:00
         * {{ 300 | timezone: false:'z' }} => +5z00
         */
        module.filter("timezone", [function() {

            return function(value, zulu, timeSeparator) {
                timeSeparator = timeSeparator || ":";
                zulu = typeof (zulu) !== "undefined" ? zulu : false;

                if (zulu && (!value || value === "0")) {

                    // Need to test for "0" because our JSON serilizer is dealing
                    // with Perl and sometimes gets 0 and other times get "0".
                    return "Z";
                }
                var hours = Math.floor(value / 60);
                var minutes = Math.abs(value % 60);
                var formattedHours = STRING.lpad(Math.abs(hours).toString(), 2, "0");

                if ( hours > 0 ) {
                    formattedHours = "+" + formattedHours;
                } else {
                    formattedHours = "-" + formattedHours;
                }
                return formattedHours + timeSeparator + STRING.lpad(minutes.toString(), 2, "0");
            };
        }]);
    }
);
