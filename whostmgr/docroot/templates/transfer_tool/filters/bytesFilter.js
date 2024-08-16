/*
# templates/transfer_tool/filters/bytesFilter.js                    Copyright(c) 2020 cPanel, L.L.C.
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

        // Main - reusable
        /**
         * Angular filter which returns a string localized with LOCALE.format_bytes
         * @return {string}
         */
        app.filter("bytes", function() {
            return function(bytes) {
                return LOCALE.format_bytes(bytes);
            };
        });
    }
);
