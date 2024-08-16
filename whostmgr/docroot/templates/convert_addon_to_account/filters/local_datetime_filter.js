/*
# convert_addon_to_account/filters/local_datetime_filter.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(["angular", "cjt/util/locale"], function(angular, LOCALE) {

    var app = angular.module("App");
    app.filter("local_datetime", function() {
        return function(input) {
            if (input === void 0 || input === null || input === "") {
                return "";
            }

            if (typeof input !== "number") {
                input = Number(input);
            }

            return LOCALE.local_datetime(input, "datetime_format_medium");
        };
    });

});
