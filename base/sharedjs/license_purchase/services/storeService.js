/*
# license_purchase/services/storeService.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    [
        "angular",
        "lodash",

        // CJT
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService"
    ],
    function(
        angular,
        _,
        LOCALE,
        PARSE,
        API,
        APIREQUEST
    ) {

        "use strict";

        // Constants
        var NO_MODULE = "";
        var USE_JSON = { json: true };

        var module = angular.module("whm.storeService", [
            "cjt2.services.api"
        ]);

        function storeServiceFactory($q, APIService) {

            // Set up the service's constructor and parent
            var StoreService = function() {
                this.accessToken = "";
            };
            StoreService.prototype = new APIService();

            var isEligibleForTrialPromise;

            // Extend the prototype with any class-specific functionality
            angular.extend(StoreService.prototype, {

                /**
                 * Checks to see whether the current server is eligible for a trial license.
                 *
                 * @param {Object} args - Object containing options
                 * @param {Boolean} args.noCache - By default, this method will return a promise from any previous
                 *                                 requests. Pass true to this argument to fetch a new response.
                 * @returns {Promise<Boolean>} - When resolved, it will contain a boolean response as to whether
                 *                               the current server is eligible for trial or not.
                 */
                isEligibleForTrial: function(args) {
                    args = args || {};

                    if (isEligibleForTrialPromise && !args.noCache) {
                        return isEligibleForTrialPromise;
                    } else {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "is_eligible_for_trial");

                        isEligibleForTrialPromise = this.deferred(apiCall).promise
                            .then(function(response) {
                                if (!response || !response.data || !response.data.hasOwnProperty("is_eligible")) {
                                    return $q.reject(
                                        LOCALE.maketext("The system failed to parse the response from the API: [_1]", "is_eligible_for_trial")
                                    );
                                }

                                return PARSE.parsePerlBoolean( response.data.is_eligible );
                            });

                        return isEligibleForTrialPromise;
                    }
                },

                /**
                 * Returns the cPanel store login link
                 * @method getLoginURL
                 * @param  {String} url The url to redirect the user to after successful store login
                 * @return {Promise} Promise that will fulfill the request.
                 */
                getLoginURL: function(url) {
                    var self = this;
                    return this._getLoginURL(url).catch(function(error) {

                        // There's no point in saving an error response. Let it retry every time
                        self._getLoginURL.cache.delete(url);
                        return $q.reject(error);
                    });
                },

                _getLoginURL: _.memoize(function(url) {

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "get_login_url");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("url_after_login", url);

                    var deferred = this.deferred(apiCall);

                    // pass the promise back to the controller
                    return deferred.promise;
                }),

                /**
                 * Validates if the returned token from the store is valid
                 * @method validateLoginToken
                 * @param {String} url The url to redirect the user to after successful store login
                 * @param {String} token The token returned from cPStore
                 * @return {Promise} Promise that will fulfill the request.
                 */
                validateLoginToken: function(token, url) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "validate_login_token");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("url_after_login", url);
                    apiCall.addArgument("login_token", token);

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Takes an authorization code and the redirect URI from the original authorization
                 * request and requests an access token from the cPStore.
                 *
                 * @async
                 * @param {string} authCode - The authorization code returned from the cPStore.
                 * @param {string} redirectUri - The URI provided to the original authorization request.
                 * @returns {Promise<string>} - Resolves with the access token.
                 * @throws {Promise<string>} - Rejects with an error message if the API indicates success but is missing the access token.
                 * @throws {Promise<string>} - Rejects with an error message from the API if there is an error.
                 */
                getAccessToken: function(authCode, redirectUri) {
                    return this.validateLoginToken(authCode, redirectUri).then(function(result) {
                        var accessToken = result && result.data && result.data[0] && result.data[0].access_token;
                        if (accessToken) {
                            return accessToken;
                        } else {
                            return $q.reject("The system failed to authenticate. Please try again");
                        }
                    });
                },

                /**
                 * Generated the order to purchase license
                 * @method generateLicenseOrder
                 * @param {String} token The token returned from cPStore
                 * @param {String} url The url to redirect the user to after checkout
                 * @return {Promise} Promise that will fulfill the request.
                 */
                generateLicenseOrder: function(token, url, isUpgrade) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "purchase_a_license");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("login_token", token);
                    apiCall.addArgument("url_after_checkout", url);

                    if (isUpgrade) {
                        apiCall.addArgument("upgrade", "1");
                    }

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Creates and completes an order for a new trial license for the server.
                 *
                 * @async
                 * @param {Object} args
                 * @param {string} args.token - An access token used to interface with the cPStore.
                 * @param {string} args.verificationCode - The verification code that will validate the user
                 *                                         for a trial license.
                 * @param {boolean} args.sendVerification - If true and the order is rejected due to missing
                 *                                          verification, a new verification code will be sent.
                 * @returns {Promise<*>} - When resolved, a new trial license has been secured.
                 */
                acquireTrialLicense: function(args) {
                    var apiArgs = {
                        provider: "cPStore",
                        login_token: args.token,
                        checkout_args: {},
                    };

                    if (args.sendVerification) {
                        apiArgs.checkout_args.send_verification = 1;
                    }
                    if (args.verificationCode) {
                        apiArgs.checkout_args.verification_code = args.verificationCode;
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "purchase_a_trial", apiArgs, null, USE_JSON);

                    var deferred = this.deferred(apiCall, this._getTransformAPIFailureOverride());
                    return deferred.promise;
                },

                /**
                 * Thrown when an operation is taking place that expects the server not to be licensed, but it already is.
                 *
                 * @typedef {Object} ServerIsLicensedError
                 * @property {boolean} serverIsLicensed - True if the server is licensed.
                 */

                /**
                 * Thrown when there is additional type information available about an API error.
                 * @typedef {Object} TypedApiError
                 * @param {boolean} isVerificationFailure - True if the error is a result of the account not being verified.
                 * @param {string} type - The type of underlying error.
                 * @param {string} email - The associated email. Only populated for verification failures.
                 * @param {string} message - The API error string.
                 */

                /**
                 * Sends a verification code to the user.
                 *
                 * @async
                 * @param {string} token - An access token used to interface with the cPStore.
                 * @returns {Promise<string>} - Resolves with the email address that the verification code has been sent to.
                 * @throws {Promise<TypedApiError>} - Rejects with a typed error object when there is an error during checkout.
                 * @throws {Promise<string>} - Rejects with an error string when there is any other API error.
                 * @throws {Promise<ServerIsLicensedError>} - Rejects with an error object when the server is already licensed.
                 */
                sendVerificationCode: function(token) {
                    var self = this;
                    return this.acquireTrialLicense({
                        token: token,
                        sendVerification: true,
                    }).then(function() {

                        /**
                         * This means that the purchase actually went through. This should not usually happen unless
                         * the user is using multiple windows to complete the initial setup. We will throw to signal
                         * to the consumer that this unintentional purchase has occurred.
                         */
                        return $q.reject({
                            serverIsLicensed: true,
                        });
                    }).catch(function(error) {
                        if (error.type === self._verificationSentErrorCode) {

                            // A new code has been sent, so we won't rethrow the error
                            return error.email;
                        } else {

                            // We have some other failure, so rethrow
                            return $q.reject(error);
                        }
                    });
                },

                _verificationSentErrorCode: "X::EmailNotVerified::EmailSent",

                /**
                 * Calls the API to run cpkeyclt to check for a valid license
                 * @method updateLicense
                 * @return {Promise} Promise that will fulfill the request.
                 */
                updateLicense: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "run_cpkeyclt");

                    // force is undocumented by design to prevent users from locking out their system
                    apiCall.addArgument("force", "1");

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Override for the default transformAPIFailure() handler in APIService so we
                 * can get the data object (that contains the error type information) as well.
                 */
                _getTransformAPIFailureOverride: function() {
                    var self = this;
                    return {

                        /**
                         * Transforms an API error into a typed error with additional information.
                         * @param {Object} resp - The API response object.
                         * @returns {TypedApiError}
                         */
                        transformAPIFailure: function(resp) {
                            if (!resp) {
                                return {};
                            }

                            var errorType = resp.data && resp.data.type;
                            return {
                                isVerificationFailure: errorType && self._isVerificationFailure(errorType),
                                type: errorType,
                                email: resp.data && resp.data.detail && resp.data.detail.data && resp.data.detail.data.email,
                                message: resp.error,
                            };
                        }
                    };
                },

                _verificationFailureRegex: /^X::EmailNotVerified/,
                _isVerificationFailure: function(errorType) {
                    return this._verificationFailureRegex.test(errorType);
                },
            });

            return new StoreService();
        }

        storeServiceFactory.$inject = ["$q", "APIService"];
        return module.factory("storeService", storeServiceFactory);
    });
