/*
# cjt/filters/startFromFilter.js                  Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.filters.startFrom", []);

        /**
         * Filter that returns an array with the elements after the specified starting position.
         * @param {Array|string} input Source array or string to be sliced
         * @param {number} start the position to begin the slice
         */
        module.filter("startFrom", function() {
            return function(input, start) {
                start = Number(start);
                if ( isNaN(start) ) {
                    start = 0;
                }
                return input.slice(start);
            };
        });
    }
);
