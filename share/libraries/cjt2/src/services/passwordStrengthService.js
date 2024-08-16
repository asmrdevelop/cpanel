/*
# cjt/services/passwordStrengthService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",
        "lodash",

        // CJT
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/performance"
    ],
    function(angular, _, CJT, LOCALE, performance) {

        var module = angular.module("cjt2.services.passwordStrength", []);

        var url = CJT.securityToken + (CJT.isUnprotected() ? "/unprotected" : "/backend" ) + "/passwordstrength.cgi";
        var lastRequest = null;
        var memoizedPasswordStrengths = {};

        /**
         * Setup the password strength API service
         */
        module.factory("passwordStrength", [ "$q", "$http", "$rootScope", function($q, $http, $rootScope) {

            /**
             * Broadcast the event
             *
             * @private
             * @method _broadcast
             * @param  {String} id
             * @param  {String} password
             * @param  {Number} strength
             */
            function _broadcast(id, password, strength) {
                $rootScope.$broadcast("passwordStrengthChange", {

                    // Password field we are validating
                    id: id,

                    // For validators to pull apart.
                    password: password,

                    // Just let the other listeners know if the password is set
                    hasPassword: password && password.length > 0 ? true : false,

                    // Strength returned by the service
                    strength: strength
                });
            }

            // return the factory interface
            return {

                /**
                 * Cancel the last pending request if it exists.
                 *
                 * @method cancelLastRequest
                 */
                cancelLastRequest: function() {
                    if (lastRequest) {
                        lastRequest.cancel();
                        lastRequest.deferred.reject({
                            canceled: true
                        });
                        CJT.debug("Canceled existing request");
                        lastRequest = null;
                    }
                },

                /**
                 * Checks if there are any pending requests for strength check.
                 *
                 * @method hasPendingRequest
                 * @return {Boolean} true if there are pending requests, false otherwise.
                 */
                hasPendingRequest: function() {
                    return lastRequest !== null;
                },

                /**
                 * Checks the strength of a password.
                 *
                 * @method checkPasswordStrength
                 * @param {String} id       The unique id for the field being evaluated.
                 * @param {String} password The password to check.
                 * @return {Promise}        A promise that resolves once the password strength is determined
                 *                          or rejects if it wasn't determined.
                 */
                checkPasswordStrength: function(id, password) {

                    // Cancel the last request if it exists
                    this.cancelLastRequest();

                    var deferred, canceler;

                    // Exit quickly if password is empty or undefined
                    if (angular.isUndefined(password) || password === "") {
                        _broadcast(id, password, 0);
                        deferred = $q.defer();
                        deferred.resolve({
                            status: 200,
                            strength: 0,
                            password: password,
                            id: id
                        });
                        return deferred.promise;
                    }

                    if (memoizedPasswordStrengths.hasOwnProperty(password)) {
                        _broadcast(id, password, memoizedPasswordStrengths[password]);
                        deferred = $q.defer();
                        deferred.resolve({
                            status: 200,
                            strength: memoizedPasswordStrengths[password],
                            password: password,
                            id: id
                        });
                        return deferred.promise;
                    }

                    // Setup and stash key items from the last request for cancellation purposes
                    canceler = $q.defer();
                    deferred = $q.defer();
                    lastRequest = {
                        cancel: function() {
                            canceler.resolve();
                        },
                        deferred: deferred
                    };

                    // Prepare the postAsForm arguments
                    var request = {
                        url: url,
                        data: {
                            password: password
                        },
                        config: {
                            timeout: canceler.promise.then(function() {
                                var stop = performance.now();
                                CJT.debug("Call to cgi password strength service canceled " + (stop - start) + " milliseconds.");
                            })
                        }
                    };

                    var start = performance.now();
                    var strength = 0;

                    $http.postAsForm(request.url, request.data, request.config).then(
                        function(response) {
                            var stop = performance.now();
                            CJT.debug("Call to cgi password strength service " + (stop - start) + " milliseconds.");

                            // We can't resolve the promise if there's no strength returned
                            if ( !angular.isUndefined(response.data.strength) ) {
                                memoizedPasswordStrengths[password] = response.data.strength;
                                strength = response.data.strength;
                                deferred.resolve({
                                    status: 200,
                                    strength: strength,
                                    password: password,
                                    id: id
                                });
                            } else {
                                deferred.reject({
                                    statusText: "Unspecified API Error", // HTTP status messages aren't localized
                                    status: response.status,
                                    strength: strength,
                                    password: password,
                                    id: id
                                });
                            }
                        },

                        // HTTP status other than 200
                        function(error) {
                            deferred.reject({
                                statusText: error.statusText,
                                status: error.status,
                                strength: strength,
                                password: password,
                                id: id
                            });
                        }
                    ).finally(function() {

                        // Done processing so clear the last request
                        lastRequest = null;

                        _broadcast(id, password, strength);
                    });

                    return deferred.promise;
                }
            };
        }]);

        return {
            url: url
        };
    }
);
