/*
# cpanel - base/webmail/jupiter/account_preferences/services/accountPrefs.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "lodash",
        "cjt/io/uapi-request",
        "cjt/modules",
        "cjt/io/api",
        "cjt/io/uapi",
        "cjt/services/APICatcher",
    ],
    function(angular, _, APIRequest) {

        "use strict";

        var MODULE_NAMESPACE = "webmail.accountPrefs.services.accountPrefs";
        var SERVICE_NAME = "AccountPrefsService";
        var MODULE_REQUIREMENTS = [ "cjt2.services.apicatcher" ];
        var SERVICE_INJECTABLES = ["APICatcher"];

        /**
         *
         * Service Factory to generate the Account Preferences service
         *
         * @module AccountPrefsService
         * @memberof webmail.accountPrefs
         *
         * @param {Object} APICatcher base service
         * @returns {Service} instance of the Domains service
         */
        var SERVICE_FACTORY = function(APICatcher) {

            var Service = function() {};

            Service.prototype = Object.create(APICatcher);

            _.assign(Service.prototype, {

                /**
                 * Wrapper for building an apiCall
                 *
                 * @private
                 *
                 * @param {String} module module name to call
                 * @param {String} func api function name to call
                 * @param {Object} args key value pairs to pass to the api
                 * @returns {UAPIRequest} returns the api call
                 *
                 * @example _apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } )
                 */
                _apiCall: function _createApiCall(module, func, args) {
                    var apiCall = new APIRequest.Class();
                    apiCall.initialize(module, func, args);
                    return apiCall;
                },

                /**
                 * Process the return value of the isMailboxAutoCreateEnabled call
                 *
                 * @param {Object} response object containing the data value
                 * @returns {Boolean} boolean value state of get_mailbox_autocreate
                 *
                 * @example _processMailboxAutoCreateResponse( { data:1 } )
                 */
                _processMailboxAutoCreateResponse: function _processPAResponse(response) {
                    return response && response.data && response.data.toString() === "1";
                },

                /**
                 * Retrieve current state of an email address's ability to auto create folders
                 *
                 * @param {String} email email address to check
                 * @returns {Promise<Boolean>} parsed value of the get_mailbox_autocreate call
                 *
                 * @example $service.isMailboxAutoCreateEnabled("foo@bar.com");
                 */
                isMailboxAutoCreateEnabled: function isMailboxAutoCreateEnabled(email) {
                    var apiCall = this._apiCall("Email", "get_mailbox_autocreate", { email: email });
                    return this._promise(apiCall).then(this._processMailboxAutoCreateResponse);
                },

                /**
                 * Enable Mailbox Auto Creation for an email address
                 *
                 * @param {String} email email address on which to enable auto creation
                 * @returns {Promise}
                 *
                 * @example $service.enableMailboxAutoCreate("foo@bar.com");
                 */
                enableMailboxAutoCreate: function enableMailboxAutoCreate(email) {
                    var apiCall = this._apiCall("Email", "enable_mailbox_autocreate", { email: email });
                    return this._promise(apiCall);
                },

                /**
                 * Disable Mailbox Auto Creation for an email address
                 *
                 * @param {String} email email address on which to enable auto creation
                 * @returns {Promise}
                 *
                 * @example $service.disableMailboxAutoCreate("foo@bar.com");
                 */
                disableMailboxAutoCreate: function disableMailboxAutoCreate(email) {
                    var apiCall = this._apiCall("Email", "disable_mailbox_autocreate", { email: email });
                    return this._promise(apiCall);
                },

                /**
                 * Wrapper for .promise method from APICatcher
                 *
                 * @param {Object} apiCall api call to pass to .promise
                 * @returns {Promise}
                 *
                 * @example $service._promise( $service._apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } ) );
                 */
                _promise: function _promise() {

                    // Because nested inheritence is annoying
                    return APICatcher.promise.apply(this, arguments);
                },
            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE,
        };
    }
);
