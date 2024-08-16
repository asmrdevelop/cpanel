/*
# templates/passwdlist/services/PasswordListService.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */
/* jshint -W089 */

define(
    [
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, APIREQUEST) {
        "use strict";

        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.apicatcher", "cjt2.services.api"]); // Fall-back for unit testing
        }

        return app.factory("PasswordListService", ["APICatcher", "APIService", function(api, apiService) {

            var NO_MODULE = "";

            /**
             * Calls WHM API to request passsword change on the supplied username and password.
             *
             * @method requestPasswordChange
             * @param {String} user      The WHM username on which to update the password.
             * @param {String} password  The new password for the WHM user to update.
             * @param {Boolean} enableDigestAuth  Enable Digest Authentication for user.
             *
             * @return {Promise}         Object that return success or failure results.
             */
            function requestPasswordChange(user, password, enableDigestAuth, syncMySQLPassword) {

                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "passwd", {
                        "user": user,
                        "password": password,
                        "enabledigest": enableDigestAuth ? "1" : "0",
                        "db_pass_update": syncMySQLPassword ? "1" : "0"
                    }
                );

                return apiService.promise(apiCall);
            }

            /**
             * Check if a user has digest authentication enabled
             *
             * @method hasDigestAuth
             *
             * @param  {String} user username to lookup
             *
             * @return {Promise} returns the apiCall promise which then returns the boolean result of the call
             *
             */
            function hasDigestAuth(user) {
                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "has_digest_auth", {
                        user: user
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    return result.data.digestauth && result.data.digestauth.toString() === "1";
                });
            }

            /**
             * Check if a user has a .my.cnf file
             *
             * @method hasMySQLCnf
             *
             * @param  {String} user username to lookup
             *
             * @return {Promise} returns the apiCall promise which then returns the boolean results of the call
             *
             */
            function hasMySQLCnf(user) {

                //
                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "has_mycnf_for_cpuser", {
                        user: user
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    return result.data.has_mycnf_for_cpuser && result.data.has_mycnf_for_cpuser.toString() === "1";
                });
            }

            return {
                requestPasswordChange: requestPasswordChange,
                hasDigestAuth: hasDigestAuth,
                hasMySQLCnf: hasMySQLCnf
            };

        }]);
    }
);
