/*
# templates/transfer_tool/filters/cpLimitToFilter.js                Copyright(c) 2020 cPanel, L.L.C.
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
         * Angular filter that limits arrays to a defined limit
         * @return {array}
         */
        app.filter("cpLimitTo", function() {
            return function(input, limit) {
                return limit ? input.slice(0, limit) : input;
            };
        });
    }
);
