/*
 * services/sshTestService.js                      Copyright(c) 2020 cPanel, L.L.C.
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
], function(
        angular,
        _,
        PARSE,
        APIREQUEST
    ) {

    var module = angular.module("whm.createSupportTicket");

    module.factory("sshTestService", [
        "$q",
        "APIService",
        function(
            $q,
            APIService
        ) {

            // Set up the service's constructor and parent
            var SshTestService = function() {};
            SshTestService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(SshTestService.prototype, {

                /**
                 * Initiates an SSH test without waiting for the response.
                 *
                 * @method startTest
                 * @param  {Number} ticketId    The ticket ID that contains the server information you wish to test.
                 * @param  {Number} serverNum   The server number (as listed in the ticket) to test. Defaults to 1.
                 * @return {Promise}            When resolved, the SSH test initiated succesfully.
                 */
                startTest: function(ticketId, serverNum) {
                    if (angular.isUndefined(serverNum)) {
                        serverNum = 1;
                    }

                    if ( !angular.isNumber(ticketId) ) {
                        throw new TypeError("Developer Error: ticketId must be a number");
                    }
                    if ( !angular.isNumber(serverNum) ) {
                        throw new TypeError("Developer Error: serverNum must be a number");
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_ssh_test_start");
                    apiCall.addArgument("ticket_id", ticketId);
                    apiCall.addArgument("server_num", serverNum);

                    return this.deferred(apiCall).promise;
                },

            });

            return new SshTestService();
        }
    ]);
});
