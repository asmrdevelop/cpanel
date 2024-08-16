/*
# rootmail/services/mailPrefService.js                      Copyright(c) 2020 cPanel, L.L.C.
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


        app.factory("mailPrefService", ["$q", "APIService",
            function($q, APIService) {

                // private  functions used within the service
                // service workhorses

                // Set up the service's constructor and parent
                var BaseService = function() {};
                BaseService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(BaseService.prototype, {

                    /**
                     * get forward location for provided user
                     *
                     * @method get_user_email_forward_destination
                     * @param  {String} user User name for which to get the user forward address.
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    get_user_email_forward_destination: function(user) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "get_user_email_forward_destination");
                        apiCall.addArgument("user", user);

                        var deferred = this.deferred(apiCall);

                        // pass the promise back to the controller
                        return deferred.promise;
                    },

                    /**
                     * set forward location for provided user
                     *
                     * @method set_user_email_forward_destination
                     * @param  {String} user User name for which to get the user forward address.
                     * @param  {String} forward_to Email address or username to forward to.
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    set_user_email_forward_destination: function(user, forward_to) {

                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "set_user_email_forward_destination");
                        apiCall.addArgument("user", user);
                        apiCall.addArgument("forward_to", forward_to);

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
