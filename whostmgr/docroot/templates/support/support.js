/*
# whostmgr/docroot/tempaltes/support/support.js   Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global angular, $, confirm, PAGE */

/**
 * Angular application that handles granting cPanel support techs access to a cPanel/WHM server.
 *
 * @module TicketSupportApp
 *
 */

var TicketSupportApp = angular.module( "TicketSupportApp", [ "ui.bootstrap", "ngSanitize" ] );
TicketSupportApp.value("PAGE", PAGE);

/**
 * Service for the ticket list that will be used by support controllers
 */
TicketSupportApp.service( "AuthorizedTickets", function() {
    this.serial = 0;
    this.auths = [];
    this.authCount = 0;
    this.closedCount = 0;

    this.getClosedCount = function() {
        return this.closedCount;
    };

    this.getAuthCount = function() {
        return this.authCount;
    };

    this.clear = function() {
        this.auths.length = 0;
        this.closedCount = 0;
    };
    this.update = function( auth, updated_auth, index ) {

        // update an existing item
        angular.forEach( auth.auth, function(v, k) {
            if (updated_auth[k] === undefined) {
                updated_auth[k] = v;
            }
        });
        updated_auth._serial = ++this.serial;
        this.authCount++;
        this.auths[auth.$parent.$index].servers[index] = updated_auth;
    };
    this.extend = function(auths) {

        // add serials
        for ( var a = 0, authLength = auths.length; a < authLength; a++ ) {
            auths[a]._serial = ++this.serial;
            for ( var s = 0, servLength = auths[a].servers.length; s < servLength; s++ ) {

                // keep track of the array index before filtering
                auths[a].servers[s]._index = s;
                auths[a].servers[s]._serial = ++this.serial;
                if ( !auths[a].servers[s].bound ) {

                    // set the unbound servers flag in the parent ticket
                    auths[a].unboundServers = true;
                }
                if ( auths[a].servers[s].auth_status === "AUTHED" ) {
                    this.authCount++;
                }
                if ((auths[a].ticket_status === "CLOSED" || auths[a].ticket_status === "UNKNOWN") && auths[a].servers[s].auth_status === "EXPIRED") {
                    this.closedCount++;
                }
            }
        }

        // now extend the list
        angular.extend( this.auths, auths );
    };
    this.list = function() {
        return this.auths;
    };
    this.remove = function(auth, index) {
        var parentTicket = this.auths[auth.$parent.$index];
        if ( parentTicket.servers.length === 1 && auth.$parent.ticket.ticket_status !== "OPEN" ) {

            if (auth.$parent.ticket.ticket_status !== "OPEN") {
                this.closedCount--;
            }

            // only one auth, remove the ticket
            this.auths.splice( auth.$parent.$index, 1 );
        } else {

            // remove individual server info
            parentTicket.servers.splice( index, 1 );
            this.auths[auth.$parent.$index]._serial = ++this.serial;
        }
    };
    this.revoke_auth = function(auth, index) {

        // unset auth_status and auth information
        // we need a new object for this so that angular recognizes the change
        var new_auth = angular.copy(auth.auth);
        new_auth._serial = ++this.serial;
        new_auth.auth_status = "NOT_AUTHED";
        delete new_auth.auth_time;
        delete new_auth.ssh_test_result;
        this.auths[auth.$parent.$index].servers[index] = new_auth;
        this.auths[auth.$parent.$index]._serial = ++this.serial;
        this.authCount--;
    };
    this.removeClosedTickets = function() {

        // remove all closed/unknown tickets
        for ( var ticketIndex = 0; ticketIndex < this.auths.length; ticketIndex++ ) {
            var ticketStatus = this.auths[ticketIndex].ticket_status;
            if ( ticketStatus === "CLOSED" || ticketStatus === "UNKNOWN") {

                // remove the ticket and update the array index
                this.auths.splice( ticketIndex, 1 );
                ticketIndex--;
            }
        }
        this.closedCount = 0;
    };
    this.set_ssh_test_result = function(auth, ssh_test_result, index) {
        var new_auth = angular.copy(auth.auth);
        new_auth._serial = ++this.serial;
        new_auth.ssh_test_result = ssh_test_result;
        this.auths[auth.$parent.$index].servers[index] = new_auth;
        this.auths[auth.$parent.$index]._serial = ++this.serial;
    };
    this.generate_alert = function(auth, alert) {

        // set the alert on the ticket
        auth.$parent.ticket.alert = alert;
    };
});

/**
 * Controller that handles listing the customer's tickets
 *
 * @method List controller
 * @param {Object} $scope The Angular scope variable
 * @param {Object} $http The Angular HTTP request object
 */
TicketSupportApp.controller( "List", [ "$scope", "$http", "AuthorizedTickets", "PAGE",
    function($scope, $http, AuthorizedTickets, PAGE) {

        // load the service with the page's initial data set
        AuthorizedTickets.extend(PAGE.tickets);

        // initial states
        $scope.firewallProblem = PAGE.firewall.problem;
        $scope.alert = undefined;
        $scope.tickets = AuthorizedTickets.list();
        $scope.formData = {};
        $scope.isFixingFirewall = false;
        $scope.isProcessing = false;
        $scope.isTesting = false;
        $scope.connectionFailure = {
            "type": "danger",
            "msg": LOCALE.maketext("Your computer is unable to contact [output,acronym,WHM, WebHost Manager]. Check the connection to your server and reload your browser.")
        };

        /**
         * POSTs the formData bound structure to the WHM backend API and handles the result alert
         */
        $scope.load = function() {

            // make the request with our form, bound data
            $scope.isProcessing = true;
            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/ticket_list?api.version=1",
                "data": $.param($scope.formData),
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {
                $scope.isProcessing = false;

                // make sure the user knows what happened
                if (undefined === data.metadata) {
                    $scope.alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    var message = data.metadata.reason.replace(/, key.*/, "");
                    $scope.alert = {
                        "type": "danger",
                        "msg": message
                    };
                } else {

                    // clear and repopulate the list
                    $scope.alert = undefined;
                    AuthorizedTickets.clear();
                    AuthorizedTickets.extend(data.data.auths);
                }
            }).error(function() {
                $scope.isProcessing = false;
                $scope.alert = $scope.connectionFailure;
            });
        };

        /**
         * Provides the count of closed or expired server authorizations to the view
         */
        $scope.getClosedCount = function() {
            return AuthorizedTickets.getClosedCount();
        };

        /**
         * Provides the count of authorized servers to the view
         */
        $scope.getAuthCount = function() {
            return AuthorizedTickets.getAuthCount();
        };

        /**
         * POSTs the formData bound structure to the WHM backend API and handles the result as an alert
         */
        $scope.grant = function(index) {

            // make the request with the list item
            this.auth.isProcessing = true;
            var auth = this,
                ticket_id = this.$parent.ticket.ticket_id;
            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/ticket_grant?api.version=1",
                "data": $.param({
                    "ticket_id": ticket_id,
                    "server_num": this.auth.server_num
                }),
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {
                auth.auth.isProcessing = false;

                // make sure the user knows what happened
                var alert;
                if (undefined === data.metadata) {
                    alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    var message = data.metadata.reason.replace(/, key.*/, "");
                    alert = {
                        "type": "danger",
                        "msg": message
                    };
                } else {

                    // construct success message
                    alert = {
                        "type": "success",
                        "msg": LOCALE.maketext( "You successfully granted access for Ticket ID “[_1]” on Server “[_2]” - “[_3]” for User “[_4]”.", data.data.ticket_id, data.data.server_num, data.data.server_name, data.data.ssh_username )
                    };

                    // update ticket
                    AuthorizedTickets.update( auth, data.data, index );

                    // clear the firewall problem flag
                    $scope.firewallProblem = false;
                }
                AuthorizedTickets.generate_alert( auth, alert );
            }).error(function() {
                auth.auth.isProcessing = false;
                AuthorizedTickets.generate_alert( auth, $scope.connectionFailure);
            });
        };

        /**
         * POSTs the formData bound structure to the WHM backend API and handles the result by manipulating the auth service
         */
        $scope.revoke = function(index) {
            var auth = this,
                ticket_id = auth.$parent.ticket.ticket_id;
            if (auth.auth.ticket_status === "CLOSED" || auth.auth.auth_status === "EXPIRED") {
                if (!confirm(LOCALE.maketext( "Ticket ID “[_1]” is closed. Do you want to revoke and remove this authorization?", ticket_id ))) {
                    return;
                }
            }
            auth.auth.isProcessing = true;
            auth.auth.isTesting    = false;
            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/ticket_revoke?api.version=1",
                "data": $.param({
                    "ticket_id": ticket_id,
                    "server_num": this.auth.server_num,
                    "ssh_username": this.auth.ssh_username
                }),
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {

                // make sure the user knows what happened
                auth.auth.isProcessing = false;
                var alert, globalAlert;
                if (undefined === data.metadata) {
                    alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    alert = {
                        "type": "danger",
                        "msg": data.metadata.reason
                    };
                } else {
                    var tmp_server_name = auth.auth.server_name !== undefined ? auth.auth.server_name : "undef";
                    var tmp_ssh_username = auth.auth.ssh_username !== undefined ? auth.auth.ssh_username : "undef";
                    alert = {
                        "type": "success",
                        "msg": LOCALE.maketext( "You successfully revoked access for Ticket ID “[_1]” on Server “[_2]” - “[_3]” for User “[_4]”.", data.data.ticket_id, data.data.server_num, tmp_server_name, tmp_ssh_username )
                    };

                    globalAlert = 0;
                    if (auth.ticket.ticket_status === "CLOSED" || auth.ticket.ticket_status === "UNKNOWN" || auth.auth.auth_status === "EXPIRED") {

                        // when the ticket is not open, and there's only one server left in it, display a global alert //
                        if (auth.ticket.ticket_status !== "OPEN" && 1 === auth.$parent.ticket.servers.length) {
                            globalAlert = 1;
                        }

                        // remove the item from the array
                        AuthorizedTickets.remove(auth, index);
                    } else {

                        // update
                        AuthorizedTickets.revoke_auth(auth, index);
                    }

                    // clear the firewall problem flag
                    $scope.firewallProblem = false;
                }

                if (globalAlert) {

                    // if we're out of tickets, do a global alert
                    $scope.alert = alert;
                } else {

                    // otherwise constrain to the relevant ticket
                    AuthorizedTickets.generate_alert( auth, alert );
                }
            }).error(function() {
                auth.auth.isProcessing = false;
                AuthorizedTickets.generate_alert( auth, $scope.connectionFailure);
            });
        };

        /**
         * POSTs the formData bound structure to the WHM backend API and handles the result as an alert
         */
        $scope.removeFromClosed = function() {

            if (!confirm(LOCALE.maketext("Are you sure you want to revoke authorization for all closed tickets and remove them from the list?"))) {
                return;
            }

            // request all closed ticket authorizations be revoked and removed
            $scope.isProcessing = true;
            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/ticket_remove_closed?api.version=1",
                "data": {},
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {
                $scope.isProcessing = false;

                // make sure the user knows what happened
                if (undefined === data.metadata) {
                    $scope.alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    var message = data.metadata.reason.replace(/, key.*/, "");
                    $scope.alert = {
                        "type": "danger",
                        "msg": message
                    };
                } else {

                    // construct success message
                    $scope.alert = {
                        "type": "success",
                        "msg": LOCALE.maketext("Successfully revoked and removed authorizations from all closed tickets.")
                    };

                    // update the list now
                    AuthorizedTickets.removeClosedTickets();
                }
            }).error(function() {
                $scope.isProcessing = false;
                $scope.alert = {
                    "type": "danger",
                    "msg": LOCALE.maketext("Failed to call backend to revoke and remove authorizations from all closed tickets!")
                };
            });
        };

        /**
         * Starts an SSH connection test via the WHM backend.
         */
        $scope.ssh_test = function(index) {
            var auth = this,
                ticket_id = auth.$parent.ticket.ticket_id;
            auth.auth.isTesting = true;
            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/ticket_ssh_test?api.version=1",
                "data": $.param({ "ticket_id": ticket_id, "server_num": this.auth.server_num }),
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {
                if (!auth.auth.isTesting) {
                    return;
                }

                // make sure the user knows what happened
                auth.auth.isTesting = false;
                var alert;
                if (undefined === data.metadata) {
                    alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    alert = {
                        "type": "danger",
                        "msg": data.metadata.reason
                    };
                } else if (data.data.result !== "SUCCESS") {

                    // let user know what happened ...
                    alert = {
                        "type": "danger",
                        "msg": LOCALE.maketext( "The [asis,SSH] test failed with the following error: “[_1]”", data.data.result ) + " " + LOCALE.maketext( "For more information, read our [output,url,_1,Grant cPanel Support Access,target,_2] documentation.", "https://go.cpanel.net/cpanelsupportaccess", "_new" )
                    };

                    // ... and set test result
                    AuthorizedTickets.set_ssh_test_result( auth, data.data.result, index );
                } else {

                    // everything was ok
                    alert = {
                        "type": "success",
                        "msg": LOCALE.maketext( "The [asis,SSH] connection test was successful for Ticket ID “[_1]” on Server “[_2]” - “[_3]” for User “[_4]”.", ticket_id, auth.auth.server_num, auth.auth.server_name, auth.auth.ssh_username )
                    };

                    // set test result
                    AuthorizedTickets.set_ssh_test_result( auth, data.data.result, index );
                }
                AuthorizedTickets.generate_alert( auth, alert );
            }).error(function() {
                if (!auth.auth.isTesting) {
                    return;
                }
                auth.auth.isTesting = false;
                AuthorizedTickets.generate_alert( auth, $scope.connectionFailure);
            });
        };

        /**
         * Starts the process of fixing the firewall configuration
         */
        $scope.fixFirewall = function() {
            $scope.isFixingFirewall = true;
            var apiProblemResolution;

            if ( $scope.firewallProblem === "NEED_SETUP" ) {
                apiProblemResolution = "ticket_whitelist_setup";
            } else {
                apiProblemResolution = "ticket_whitelist_unsetup";
            }

            $http({
                "method": "POST",
                "url": CPANEL.security_token + "/json-api/" + apiProblemResolution + "?api.version=1",
                "headers": { "Content-Type": "application/x-www-form-urlencoded" }
            }).success(function(data) {
                if (!$scope.isFixingFirewall) {
                    return;
                }

                if (undefined === data.metadata) {
                    $scope.alert = {
                        "type": "danger",
                        "msg": data.cpanelresult.error
                    };
                } else if (!data.metadata.result) {
                    $scope.alert = {
                        "type": "danger",
                        "msg": data.metadata.reason
                    };
                } else {

                    // unset the problem flag
                    $scope.firewallProblem = false;

                    $scope.alert = {
                        "type": "success",
                        "msg": LOCALE.maketext( "The server’s firewall configuration has been updated." )
                    };

                }
                $scope.isFixingFirewall = false;
            }).error(function() {
                if (!$scope.isFixingFirewall) {
                    return;
                }

                $scope.alert = $scope.connectionFailure;
                $scope.isFixingFirewall = false;
            });
        };
    }
]);

/**
 * Filter that converts date strings to friendly messages
 *
 * @method fromNow filter
 * @param {Object} dateString A datetime in epoch format
 */
TicketSupportApp.filter( "fromNow", function() {
    return function(dateString) {
        var current_date = new Date();
        var current_epoch = current_date.getTime() / 1000;
        var days_passed = ( current_epoch - dateString ) / ( 3600 * 24 );
        if (days_passed <= 2.0) {
            var passed_date = new Date(dateString * 1000);

            // adjust days_passed to prevent rounding issues
            days_passed = current_date.getDay() - passed_date.getDay();
            if (days_passed < 0) {

                // accommodate current_date being Sunday (0) and grant from day before Saturday (6)
                days_passed += 7.0;
            }
            if (days_passed === 1) {
                return LOCALE.maketext("Yesterday");
            } else if (days_passed >= 2) {
                return LOCALE.maketext( "[quant,_1,day,days] ago.", days_passed );
            }
            return LOCALE.maketext("Today");
        } else if (days_passed < 7.0) {
            return LOCALE.maketext( "[quant,_1,day,days] ago.", parseInt(days_passed, 10) );
        } else if (days_passed < 14.0) {
            return LOCALE.maketext("A week ago.");
        }
        return LOCALE.maketext( "[quant,_1,week,weeks] ago.", Math.ceil(days_passed / 7.0) );
    };
});

/**
 * A filter that returns an array of server authorization objects with IP addresses bound to this server
 *
 * @method boundServerFilter filter
 * @param {boolean} showAllServers A boolean value to alternatively return all servers
 */
TicketSupportApp.filter( "boundServerFilter", function() {
    return function(servers, showAllServers) {
        if ( showAllServers ) {
            return servers;
        } else {
            var boundServers = [];
            angular.forEach(servers, function(server) {
                if ( server.bound ) {
                    boundServers.push(server);
                }
            });
            return boundServers;
        }
    };
});
