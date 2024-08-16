/*
# cjt/filters/replaceFilter.js                    Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.filters.replace", []);

        /**
         * Filter that replaces a string in a string with something else.
         *
         * @name  replace
         * @param {String} value     Value to filter.
         * @param {String} match     Match pattern.
         * @param {String} [replace] Replace pattern.
         */
        module.filter("replace", function() {
            return function(value, match, replace) {
                if (!value) {
                    return value;
                }

                // Setup up defaults
                match = match || "";
                replace = replace || "";

                var expression = new RegExp(match, "g");
                return value.replace(expression, replace);
            };
        });
    }
);
