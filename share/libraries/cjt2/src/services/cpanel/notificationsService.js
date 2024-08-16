/*
 * _assets/services/cpanel/notificationsService.js          Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/uapi-request",
        "cjt/io/uapi"  // IMPORTANT: Load the driver so its ready
    ],
    function(angular, API, APIREQUEST, APIDRIVER) {
        "use strict";

        var module = angular.module("cjt2.services.cpanel.notifications", []);

        /**
         * Setup the notifications count API service
         */
        module.factory("notificationsService", ["$q", function($q) {

            /**
             * Get number of notifications.
             *
             * @method getCount
             * @async
             * @return {Promise.<Number>} - Promise resolves to the number of notifications.
             * @throws {Promise.<String>} - If the api call returns a failed status, the error is returned in the rejected promise.
             */
            function getCount() {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("Notifications", "get_notifications_count");

                var deferred = $q.defer();

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller
                return deferred.promise;
            }

            // return the factory interface
            return {
                getCount: getCount
            };
        }]);
    }
);
