/*
 * views/startController.js                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "cjt/util/query",
    "cjt/services/popupService",
    "cjt/services/alertService",
    "app/services/ticketService",
    "app/services/ticketUrlService",
    "app/services/oauth2PopupService",
    "app/services/wizardApi"
], function(
        angular,
        QUERY_STRING_UTILS
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("startController", [
        "$scope",
        "pageState",
        "alertService",
        "popupService",
        "ticketService",
        "ticketUrlService",
        "oauth2PopupService",
        "wizardApi",
        "wizardState",
        function(
            $scope,
            pageState,
            alertService,
            popupService,
            ticketService,
            ticketUrlService,
            oauth2PopupService,
            wizardApi,
            wizardState
        ) {
            angular.extend($scope, {
                show: {
                    hackQuestion: false
                },
                hacked: "unspecified",
                hasCloudLinux: pageState.has_cloud_linux ? true : false,
                hasLiteSpeed: pageState.has_lite_speed ? true : false
            });

            if (ticketService.getAuthState()) {
                if (pageState.tos && pageState.tos.accepted) {

                    // For resets only
                    wizardState.maxSteps = 3;
                } else {
                    wizardState.maxSteps = 4;
                }
            } else {
                if (pageState.tos && pageState.tos.accepted) {

                    // For resets only
                    wizardState.maxSteps = 6;
                } else {
                    wizardState.maxSteps = 7;
                }
            }

            if (!pageState.is_cpanel_direct) {
                wizardState.maxSteps++;
            }

            wizardApi.configureStep();
            wizardApi.reset(true);
            alertService.clear();

            /**
             * The user has determined that he or she wants to get support for this server.
             * If it's DNS only, we will send them to the ticket system. Otherwise, we find
             * out if they've been compromised.
             *
             * @method selectThisServer
             */
            $scope.selectThisServer = function() {
                if (pageState.is_dns_only) {

                    // Navigate to the ticket system for dns only tickets
                    var url = $scope.getTicketUrl("dnsonly");
                    popupService.openPopupWindow(url, "tickets", { newTab: true }).focus();
                } else if ( ticketService.getAuthState() ) {
                    if (!pageState.is_cpanel_direct) {
                        wizardApi.loadView("/supportinfo", null, { clearAlerts: true });
                    } else if (pageState.tos && pageState.tos.accepted) {
                        wizardApi.loadView("/grant", null, { clearAlerts: true });
                    } else {
                        wizardApi.loadView("/tos", null, { clearAlerts: true });
                    }
                    wizardApi.showFooter();
                    wizardApi.next();
                } else {
                    $scope.show.hackQuestion = true;
                    wizardApi.next();
                }
            };

            /**
             * This gets the appropriate URL for creating a particular type of ticket.
             *
             * @method getTicketUrl
             * @type {String}     The type of ticket being created
             * @return {String}   The URL for creating that type of ticket
             */
            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

            /**
             * Move back from the get started state.
             *
             * @method moveBack
             */
            $scope.moveBack = function() {
                $scope.show.hackQuestion = false;
                wizardApi.previous();
            };

            /**
             * We've determined at this point that the ticket is for this server and the
             * server isn't compromised. If they are already authenticated against the
             * customer portal, we dive right into the TOS. Otherwise, we need to open
             * the OAuth pop-up.
             *
             * @method startTicket
             */
            $scope.startTicket = function() {
                if (ticketService.getAuthState()) {

                    // Navigate to next view
                    wizardApi.loadView("/tos", null, { clearAlerts: true });
                    wizardApi.showFooter();
                    wizardApi.next();
                } else {

                    // Show OAUTH window
                    var popup = oauth2PopupService.show(
                        $scope,
                        function(reason) {
                            if (reason !== "closed") {
                                return;
                            }

                            // If the pop-up is closed before we get the code back, we should take
                            // them to the error page.
                            wizardApi.loadView("/authorize-customer-portal/error", null, {
                                replaceState: true
                            });
                        },
                        function(apiError) {
                            wizardApi.loadView("/authorize-customer-portal/error", null, {
                                replaceState: true
                            });
                        }
                    );
                    popup.focus();

                    wizardApi.loadView("/authorize-customer-portal/authorizing", null, { clearAlerts: true });
                    wizardApi.next();
                }
            };
        }
    ]);
});
