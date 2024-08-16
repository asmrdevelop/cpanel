/*
# cjt/filters/jsonFilter.js                       Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.filters.json", []);

        /**
         * Filter that converts a JavaScript object to a formated JSON text string.  Primarily intended for diagnostic/debugging
         * usage, but may be used anywhere
         *
         * @name  json
         * @type  filter
         * @param {String}   value   Value to filter.
         * @param {String}   [indent]  Characters to use to indent. Same as JSON.stringify 3rd argument. Defaults to 2 spaces.
         * @param {Function} [fnFilter] Optional filter function to apply to the value to remove items we don't want to print. Same as JSON stringify 2nd argument. Defaults to undefined.
         * @returns
         * @example
         *
         * If scope.config = { a: 'a' };
         *
         * And on the template you have:
         *
         *     {config| json}
         *
         * This yields something like:
         *
         *  {
         *    'a': 'a'
         *  }
         *
         * With a indent argument:
         *
         *     {config| json: '\t'}
         *
         * This yields something like:
         *
         *  {
         *  \t'a': 'a'
         *  }
         */
        module.filter("json", [function() {
            return function(value, indent, fnFilter) {

                // Setup the defaults
                if (angular.isUndefined(indent)) {
                    indent = "  ";
                }

                if (angular.isUndefined(fnFilter)) {
                    fnFilter = null;
                }

                // Filter the value.
                try {
                    return JSON.stringify(value, fnFilter, indent);
                } catch (e) {
                    return e;
                }
            };
        }]);
    }
);
