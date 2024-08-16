/*
 * services/ticketService.js                       Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "lodash",
    "cjt/util/parse",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/services/APIService",
    "cjt/services/whm/oauth2Service"
], function(
        angular,
        _,
        PARSE,
        APIREQUEST
    ) {

    var module = angular.module("whm.createSupportTicket");

    module.factory("ticketService", [
        "$q",
        "APIService",
        "oauth2Service",
        "pageState",
        function(
            $q,
            APIService,
            oauth2Service,
            pageState
        ) {

            // The state of the cPanel & WHM server's access to the Customer Portal
            // If true, then we have an OAuth token on the server
            var _authState = false;

            // Set up the service's constructor and parent
            var TicketService = function() {};
            TicketService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(TicketService.prototype, {

                /**
                 * Exchanges an OAuth code from the Customer Portal for an OAuth token that will be stored
                 * in the server's session data.
                 *
                 * @method verifyCode
                 * @param  {String} code           The OAuth code received from the Customer Portal that we want to verify
                 *                                 and exchange for a token.
                 * @param  {String} redirect_uri   The redirect_uri that was provided with the initial authorization request.
                 * @return {Promise}               When resolved, the code was successfully exchanged for an OAuth token and
                 *                                 that token is stored in the server-side session data.
                 */
                verifyCode: function(code, redirect_uri) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_validate_oauth2_code");
                    apiCall.addArgument("code", code);
                    apiCall.addArgument("redirect_uri", redirect_uri);

                    var self = this;
                    return this.deferred(apiCall).promise.then(function(data) {
                        self.setAuthState(true);
                        return data;
                    }).catch(function(error) {
                        self.setAuthState(false);
                        return $q.reject(error);
                    });
                },

                /**
                * Launches an API query to retrieve the Support Information about the license provider.
                *
                * @method fetchSupportInfo
                * @return {Promise}                      When resolved, either the agreement will be available or
                *                                        retrieval will have failed.
                */
                fetchSupportInfo: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_get_support_info");

                    return this.deferred(apiCall).promise.then(function(result) {
                        return result;
                    });
                },

                /**
                * Launches an API query to retrieve the Technical Support Agreement and related metadata.
                *
                * @method fetchTechnicalSupportAgreement
                * @return {Promise}                      When resolved, either the agreement will be available or
                *                                        retrieval will have failed.
                */
                fetchTechnicalSupportAgreement: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_get_support_agreement");

                    if (pageState.tos) {
                        return $q(function(resolve, reject) {
                            resolve(pageState.tos);
                        });
                    }

                    return this.deferred(apiCall).promise.then(function(result) {
                        pageState.tos = result.data; // only on success
                        pageState.tos.accepted = PARSE.parsePerlBoolean(pageState.tos.accepted);
                        return result;
                    });
                },

                /**
                * Update the ticket system to show that the currently OAuth2 user has seen
                * the support agreement.
                *
                * @method updateAgreementApproval
                * @return {Promise}                      When resolved, the current version of the agreement
                *                                        will be marked as seen.
                */
                updateAgreementApproval: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_update_service_agreement_approval");
                    apiCall.addArgument("version", pageState.tos.version);

                    return this.deferred(apiCall).promise.then(function() {
                        pageState.tos.accepted = true;
                    });
                },

                /**
                 * Create a stub ticket so we can initiate other requests that depend
                 * on there being a ticket already.
                 *
                 * @return {Number} The ticket id of the stub ticket.
                 */
                createStubTicket: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_create_stub_ticket");

                    return this.deferred(apiCall).promise.then(function(result) {
                        var ticketId = result.data.ticket_id;
                        var secId = result.data.secure_id;
                        pageState.ticketId = ticketId;
                        pageState.secId = secId;
                        return ticketId;
                    });
                },

                grantAccess: function() {
                    if (!pageState.ticketId) {
                        throw "You do not have a ticket yet, so you can not grant access. Call createStubTicket() first.";
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_grant");
                    apiCall.addArgument("ticket_id", pageState.ticketId);
                    apiCall.addArgument("secure_id", pageState.secId);
                    apiCall.addArgument("server_num", 1);
                    apiCall.addArgument("ssh_username", "root"); // TODO: Will be dynamic after we get wheel user creation

                    return this.deferred(apiCall).promise;
                },

                /**
                 * A simple getter for the authorization state.
                 *
                 * @method getAuthState
                 * @return {Boolean}   True if we have a token and the server is authorized.
                 */
                getAuthState: function() {
                    return _authState;
                },

                /**
                 * A simple setter for the authorization state.
                 *
                 * @method setAuthState
                 * @param {Boolean} state   The new authorization status.
                 */
                setAuthState: function(state) {
                    if (_.isBoolean(state)) {
                        _authState = state;
                    } else {
                        throw new TypeError("The new state must be a boolean value.");
                    }
                }

            });

            return new TicketService();
        }
    ]);
});
