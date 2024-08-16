/*
# templates/greylist/filters/ipWrapFilter.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "moment"
    ], function(angular, moment) {

        var app = angular.module("App");

        /**
         * Filter that returns a relative version of a date.
         * Unfortunately, for this to work with localization, you need to set
         * the locale using moment.locale() inside of the app where you use
         * this directive.
         *
         * @example
         *
         * Default:
         * Input => <div>{{ "2015-05-03 16:30:10" | relativeTime }}</div>
         * Output => in 2 months
         *
         * With suffix option set to true:
         * Input => <div>{{ "2015-05-03 16:30:10" | relativeTime }}</div>
         * Output => 2 months
         *
         */
        app.filter("relativeTime", function() {

            var relativeTimeFilter = function(input, utcOffset, removeSuffix) {
                removeSuffix = removeSuffix || false;
                if (input) {

                    // NOTE: our input is not in ISO-8601 format, so we need to fix it up
                    var offset_type = utcOffset < 0 ? "-" : "+";
                    var utcOffset_int = Math.abs(utcOffset);
                    var hh = utcOffset_int / 60;
                    var mm = utcOffset_int % 60;

                    // pad the hours
                    if (hh < 10) {
                        hh = "0" + hh;
                    }

                    // pad the minutes
                    if (mm < 10) {
                        mm = "0" + mm;
                    }
                    var tzOffsetStr = offset_type + hh + mm;
                    return moment.utc(input + tzOffsetStr, "YYYY-MM-DD HH:mm:ssZ").fromNow(removeSuffix);
                } else {
                    return moment.utc().fromNow(removeSuffix);
                }
            };

            return relativeTimeFilter;
        });
    }
);
