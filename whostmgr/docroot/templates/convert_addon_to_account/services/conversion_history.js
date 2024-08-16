/*
# convert_addon_to_account/services/conversion_history.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        var app = angular.module("App");

        var conversionHistory = app.factory("ConversionHistory", ["$q", function($q) {

            var store = {};
            store.conversions = [];

            /**
             * Gets the details for a conversion
             *
             * @method getDetails
             * @param {Number} job_id - The job id of the desired conversion.
             * @return {Object} An object consisting of conversion details and steps.
             */

            store.getDetails = function(job_id) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_fetch_conversion_details");
                apiCall.addArgument("job_id", job_id);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * Gets the current status for a conversion
             *
             * @method getJobStatus
             * @param {Number} job_ids - An array job ids of the desired conversions.
             * @return {Object} An object consisting of status information
             */

            store.getJobStatus = function(job_ids) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_get_conversion_status");
                var jobIdCount = job_ids.length;
                var i = 0;

                for (; i < jobIdCount; i++) {
                    apiCall.addArgument("job_id" + "-" + i, job_ids[i]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * Fetches all the conversion jobs
             *
             * @method load
             * @return {Array} An arrary of conversion jobs.
             */
            store.load = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_list_conversions");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            store.conversions = response.data;
                            deferred.resolve(store.conversions);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            return store;
        }]);

        return conversionHistory;
    }
);
