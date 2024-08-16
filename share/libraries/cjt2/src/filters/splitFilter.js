/*
# cjt/filters/splitFilter.js                      Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.filters.split", []);

        /**
         * Filter that splits a string on a pattern into an array.
         *
         * @name  split
         * @param {String} value   Value to filter.
         * @param {String} [match] Optional match pattern, defaults to \n
         */
        module.filter("split", function() {
            return function(value, match) {
                if (!value) {
                    return [];
                }

                // Setup up defaults
                match = match || "\n";

                var expression = new RegExp(match, "g");
                return value.split(expression);
            };
        });
    }
);
