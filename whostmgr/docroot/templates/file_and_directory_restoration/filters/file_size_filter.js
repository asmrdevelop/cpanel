/*
# file_and_directory_restoration/filters/file_size_filter.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale"
    ],
    function(angular, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("whm.fileAndDirectoryRestore"); // For runtime
        } catch (e) {
            app = angular.module("whm.fileAndDirectoryRestore", []); // Fall-back for unit testing
        }

        app.filter("convertedSize", function() {
            return function(size) {
                if (typeof size !== "number" || isNaN(size)) {
                    return LOCALE.maketext("N/A");
                }
                return LOCALE.format_bytes(size);
            };
        });
    });
