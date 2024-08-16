/*
# cjt/filters/rangeFilter.js                      Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.filters.range", []);

        /**
         * The range filter returns an array that can populate ng-repeat.
         * @input {Array} input Source array, will be emptied
         * @min {number} range begin value
         * @max {number} range end value
         * @reverse {bool} flag to output array in reverse order
         * @step {number} step interval
         */
        module.filter("range", function() {
            return function(input, min, max, reverse, step) {
                step = step || 1;

                // Depending on one or two inputs
                var trueMin = max ? min : 0,
                    trueMax = max || min;
                input = [];
                for (var i = trueMin; i <= trueMax; i += step) {
                    input.push(i);
                }
                if (reverse) {
                    input = input.reverse();
                }
                return input;
            };
        });
    }
);
