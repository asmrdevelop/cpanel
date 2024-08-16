/*
# templates/contact_manager/filters/splitOnComma.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
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

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Filter to split comma delimited strings
         * @param  {string} input
         * @param  {number} limit
         * @return {array}
         */
        app.filter("splitOnComma", function() {
            return function(input, limit) {

                // If it's not a string we got an array somehow, lets punt it back
                if (typeof input !== "string" ) {
                    return input;
                }

                // If no comma, lets also punt it
                var commaRegex = new RegExp(",");
                if (!commaRegex.test(input)) {
                    return [input];
                }

                // We use 5 as a default since this will give 3 + message about more listed
                limit = limit || 5;

                // This assume we are using a comma delimited list, this will break if strings with commas are valid
                var items = input.split(",");

                if ( items.length < limit ) {
                    return items;
                } else {

                    // If the limit is 5 we want to always use 4 or less lines, since the message takes up one
                    // this means we do limit-2
                    var newItems = items.slice(0, limit - 2);
                    newItems.push(LOCALE.maketext(" … and [numf,_1] more", (items.length - (limit - 2))));

                    return newItems;
                }
            };
        });

        /**
         * Filter to split comma delimited strings for title attribute
         * @param  {string} input
         * @return {string}
         */
        app.filter("splitOnCommaForTitle", function() {
            return function(input) {

                // If it's not a string we got an array somehow, lets punt it back
                if (typeof input !== "string" ) {
                    return input;
                }

                // If no comma, lets also punt it
                var commaRegex = new RegExp(",");
                if (!commaRegex.test(input)) {
                    return input;
                }

                var items = input.split(",");
                return items.join(",\n");
            };
        });
    }
);
