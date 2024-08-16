/*
# templates/contact_manager/services/VerifyNotificationService.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }


        app.factory("verifyNotificationService", ["$q", "APIService",
            function($q, APIService) {

                // Set up the service's constructor and parent
                var BaseService = function() {};
                BaseService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(BaseService.prototype, {

                    /**
                     * get forward location for provided user
                     *
                     * @method
                     * @param  {String}
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    verify_service: function(verification_api) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, verification_api);

                        var deferred = this.deferred(apiCall);

                        // pass the promise back to the controller
                        return deferred.promise;
                    },
                });

                return new BaseService();
            }
        ]);
    }
);
