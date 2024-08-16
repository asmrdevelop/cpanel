/*
# templates/backup_migration/services/backupMigrationAPI.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
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
        var app = angular.module("whm.backupMigration");

        var backupMigrationAPI = app.factory("backupMigrationAPI", ["$q", function($q) {

            var backupMigrationAPI = {};

            backupMigrationAPI.run_migration = function(keepConfig) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "convert_and_migrate_from_legacy_config");

                if (keepConfig) {
                    apiCall.addArgument("no_convert", "1");
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.metadata);
                    });

                return deferred.promise;
            };

            return backupMigrationAPI;
        }]);

        return backupMigrationAPI;
    }
);
