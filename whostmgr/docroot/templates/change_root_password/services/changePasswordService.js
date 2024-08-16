/*
 * changePasswordService.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
define(
    [
        "angular",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST) {

        // Get the current application
        var app = angular.module("whm.changeRootPassword");

        app.factory("changePasswordService", ["$q", "APIService", function($q, APIService) {
            var ChangePasswordService = function() {};
            ChangePasswordService.prototype = new APIService();

            angular.extend(ChangePasswordService.prototype, {

                /**
                 * Calls WHM API to request passsword change on the supplied username and password.
                 *
                 * @method requestPasswordChange
                 * @param {String} user      The WHM username on which to update the password.
                 * @param {String} password  The new password for the WHM user to update.
                 *
                 * @return {Promise}         Object that return success or failure results.
                 */
                requestPasswordChange: function(user, password) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "passwd");
                    apiCall.addArgument("user", user);
                    apiCall.addArgument("password", password);

                    return this.deferred(apiCall).promise
                        .then(function(response) {
                            return response;
                        })
                        .catch(function(error) {
                            return $q.reject(error);
                        });
                }
            });
            return new ChangePasswordService();
        }]);
    }
);
