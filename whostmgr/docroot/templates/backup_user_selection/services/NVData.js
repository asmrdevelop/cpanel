/*
# templates/backup_user_selection/services/NVData.js
                                                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, _, API, APIREQUEST, APIDRIVER) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("whm.backupUserSelection");

        var nvdata = app.factory("NVData", ["$q", function($q) {
            var obj = {};

            obj.get = function(key) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "nvget");

                apiCall.addArgument("key", key);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var obj = response.data.nvdatum;
                            var returnObj = {};

                            returnObj.key = obj.key;
                            if (Array.isArray(obj.value)) {
                                if (obj.value.length === 1) {
                                    returnObj.value = obj.value[0];
                                } else {
                                    returnObj.value = obj.value;
                                }
                            } else {
                                returnObj.value = obj.value;
                            }

                            deferred.resolve(returnObj);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;

            };

            obj.set = function(key, value) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "nvset");

                apiCall.addArgument("key1", key);
                apiCall.addArgument("value1", value);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var obj;
                            var returnObj = {};

                            if (typeof response.data.nvdatum !== "undefined") {
                                obj = response.data.nvdatum;
                            } else {
                                obj = response.data;
                            }

                            if (Array.isArray(obj) && obj.length > 0) {
                                returnObj.key = obj[0].key;
                                returnObj.value = obj[0].value;
                            }

                            returnObj.status = response.status;

                            deferred.resolve(returnObj);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;

            };

            return obj;
        }]);

        return nvdata;
    }
);
