/*
# templates/yumupdate/services/yumAPI.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var yumAPI = app.factory("YumAPI", ["$q", function($q) {

            var yumAPI = {};

            yumAPI.run_update = function(kernel) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_upgrade");
                apiCall.addArgument("kernel", kernel);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            yumAPI.tailing_log = function(buildID, offset) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_get_build_log");

                // Send the pid
                apiCall.addArgument("build", buildID);
                apiCall.addArgument("offset", offset);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            return yumAPI;
        }]);

        return yumAPI;
    }
);
