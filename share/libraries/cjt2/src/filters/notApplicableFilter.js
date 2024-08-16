/*
# cjt/filters/notApplicableFilter.js              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale"
    ],
    function(angular, LOCALE) {

        var FULL_NOT_APPLICABLE = LOCALE.maketext("Not Applicable");
        var ABBR_NOT_APPLICABLE = LOCALE.maketext("N/A");

        var module = angular.module("cjt2.filters.na", []);

        /**
         * Filter that converts null, undefined and empty values to "N/A" or "Not Applicable".
         *
         * @name  na
         * @param {String} value   Value to filter.
         * @param {Boolean} [fullWord] Optional use the full word if true, otherwise use the abbreviated form. Uses the abbreviated form if not defined.
         * @example
         */
        module.filter("na", [function() {
            return function(value, fullWord, inline) {

                // If the value is falsy and not 0, return N/A abbreviation or full text
                if (!value && value !== 0) {
                    return (fullWord ? FULL_NOT_APPLICABLE : ABBR_NOT_APPLICABLE);
                }

                // Otherwise just pass the value through
                else {
                    return value;
                }
            };
        }]);

        return {
            FULL_NOT_APPLICABLE: FULL_NOT_APPLICABLE,
            ABBR_NOT_APPLICABLE: ABBR_NOT_APPLICABLE
        };
    }
);
