/*
# cjt/filters/qaSafeIDFilter.js                      Copyright(c) 2020 cPanel, L.L.C.
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

        var app;

        // Setup the App
        app = angular.module("cjt2.filters.qaSafeID", []);

        /**
         * Filter that creates a qa-safe id for dom elements based on a string
         *
         * @name  qaSafeID
         * @param {String} value   Value to filter.
         * @example
         *
         * id="{{ "-@_test_email-id@banana.com" | qaSafeID }}" // test_email-id_banana_com
         *
         */
        app.filter("qaSafeID", function() {
            return function(value) {

                // requirements based on w3 standard
                // http://www.w3.org/TR/html401/types.html#type-name
                // "ID and NAME tokens must begin with a letter ([A-Za-z]) and may be followed
                //   by any number of letters, digits ([0-9]), hyphens ("-"), underscores ("_"),
                //   colons (":"), and periods (".")."

                var adjustedValue = value;

                // Must Start w/ [A-Za-z]

                adjustedValue = adjustedValue.replace(/^[^A-Za-z]+/, "");

                // Remove Disallowed characters (based on HTML4 Standard)
                // Additionally removing periods as a precaution

                adjustedValue = adjustedValue.replace(/[^A-Za-z0-9-_:]/g, "_");

                return adjustedValue;
            };
        });

    }
);
