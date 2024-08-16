/*
# cjt/filters/nospaceFilter.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {
        "use strict";

        var module = angular.module("cjt2.filters.nospace", []);

        /**
         * Filter that removes extra white-space from values.
         * @example
         */
        module.filter("nospace", function() {
            return function(value) {
                return (!value) ? "" : value.replace(/ /g, "");
            };
        });
    }
);
