/*
 * support/create_support_ticket/services/oauthPopupService.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "cjt/util/query",
        "cjt/services/windowMonitorService",
        "cjt/services/whm/oauth2Service",
        "cjt/services/alertService",
        "app/services/wizardApi"
    ],
    function(angular, QUERY) {

        var app = angular.module("whm.createSupportTicket");
        app.service("oauth2PopupService", [
            "pageState",
            "alertService",
            "oauth2Service",
            "popupService",
            "ticketService",
            "windowMonitorService",
            "wizardApi",
            function(
                pageState,
                alertService,
                oauth2Service,
                popupService,
                ticketService,
                windowMonitorService,
                wizardApi) {

                /**
                 * Gets the OAuth endpoint from the oauth2Service, opens the pop-up to that endpoing,
                 * and sets up a callback for the redirect, which exchanges the code for the OAuth
                 * token.
                 *
                 * @method _createAuthPopup
                 * @return {Window}   A reference to the pop-up window created
                 */
                function _createAuthPopup($scope, errorCb) {
                    var popup;
                    var oauth2 = pageState.oauth2;

                    oauth2Service.initialize(oauth2.endpoint, oauth2.params);
                    oauth2Service.setCallback(function oauth2Success(queryString) {

                        // We no longer need to monitor the pop-up for a premature close and we don't
                        // want the monitor to think that something went wrong, so clear it.
                        windowMonitorService.stop(popup);

                        // Send the client to the verification spinner.
                        wizardApi.loadView("/authorize-customer-portal/verifying", null, {
                            replaceState: true
                        });

                        // Exchange the code for a token. The token is saved in the session data on the
                        // server and not on the client.
                        var parsed = QUERY.parse_query_string(queryString);
                        ticketService.verifyCode(parsed.code, parsed.redirect_uri).then(function() {

                            // All went well...
                            // Lookup support info if the license is not from cPanel, otherwise go to the TOS.
                            if (!pageState.is_cpanel_direct) {
                                wizardApi.loadView("/supportinfo", null, {
                                    clearAlerts: true,
                                    replaceState: true
                                });
                            } else {
                                wizardApi.loadView("/tos", null, {
                                    clearAlerts: true,
                                    replaceState: true
                                });
                            }
                            wizardApi.showFooter();
                            wizardApi.next();

                        }).catch(function(error) {
                            alertService.add({
                                message: error,
                                type: "danger",
                                replace: false
                            });

                            if (errorCb) {
                                errorCb(error);
                            }
                        });
                    });

                    popup = popupService.openPopupWindow(oauth2Service.getAuthUri(), "authorize_customer_portal", {
                        autoCenter: true,
                        height: 415,
                        width: 450
                    });

                    return popup;
                }

                return {

                    /**
                     * Popup the oauth2 dialog and setup the callback and monitor.
                     *
                     * @param  {Scope}   $scope    Scope for the controller calling this. Note it must be
                     *                             passed since it can not be injected in a service like it
                     *                             can in a controller.
                     * @param  {Function} closedCb Callback to call when the monitor notices the dialog is closed.
                     * @param  {Function} errorCb  Callback to call if the verification step errors out.
                     * @return {Window}            The window handle for the popup window.
                     */
                    show: function($scope, closedCb, errorCb) {
                        var popup = _createAuthPopup($scope, errorCb);
                        windowMonitorService.start(popup, closedCb);
                        return popup;
                    }
                };
            }
        ]);


    }
);
