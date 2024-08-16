/*
# templates/transfer_tool/filters/startFromFilter.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Angular filter which returns array started at position defined by start
         * @return {array}
         */
        app.filter("startFrom", function() {
            return function(input, start) {
                if (input && angular.isArray(input)) {
                    start = Number(start); // parse to int
                    return input.slice(start);
                }
            };
        });
    }
);
