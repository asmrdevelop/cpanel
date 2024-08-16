/*
# convert_addon_to_account/services/account_packages.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
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
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var packagesFactory = app.factory("AccountPackages", ["$q", function($q) {

            var pkg = {};

            pkg.packages = [];

            /**
             * Fetch the list of packages from the listpkgs API call.
             *
             * @method listPackages
             * return {Promise} a promise that on success, returns an array of packages
             * and on error, an error object.
             */
            pkg.listPackages = function() {
                if (pkg.packages.length > 0) {
                    return $q.when(pkg.packages);
                } else {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "listpkgs");

                    return $q.when(API.promise(apiCall.getRunArguments()))
                        .then(function(response) {
                            response = response.parsedResponse;
                            if (response.status) {
                                pkg.packages = response.data;
                                return pkg.packages;
                            } else {
                                return $q.reject(response.meta);
                            }
                        });
                }
            };

            return pkg;
        }]);

        return packagesFactory;
    }
);
