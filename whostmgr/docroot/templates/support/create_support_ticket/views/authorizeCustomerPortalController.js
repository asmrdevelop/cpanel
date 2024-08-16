/*
 * views/authorizeCustomerPortalController.js      Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "cjt/util/locale",
    "cjt/services/alertService",
    "cjt/directives/loadingPanel",
    "app/services/oauth2PopupService",
    "app/services/ticketUrlService",
    "app/services/wizardApi"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("authorizeCustomerPortalController", [
        "$scope",
        "$routeParams",
        "alertService",
        "wizardApi",
        "oauth2PopupService",
        "ticketUrlService",
        function(
            $scope,
            $routeParams,
            alertService,
            wizardApi,
            oauth2PopupService,
            ticketUrlService
        ) {

            if (!wizardApi.verifyStep(/authorize-customer-portal\/.*$/)) {
                return;
            }

            $scope.$watch(
                function() {
                    return $routeParams.status;
                },
                function() {
                    $scope.status = $routeParams.status;

                    if ($scope.status === "error") {

                        /* If there is already an error displayed (e.g., from an API failure),
                         * don't bother displaying this generic error. */
                        if (!alertService.getAlerts().length) {
                            alertService.add({
                                message: LOCALE.maketext("The [asis,cPanel Customer Portal] authorization window appears closed, but the server did not receive an authorization response."),
                                type: "danger",
                                replace: true,
                                id: "closed-auth-window"
                            });
                        }
                    } else if ($scope.status !== "authorizing" &&
                               $scope.status !== "verifying" ) {
                        wizardApi.reset();
                    } else if ($scope.status === "verifying") {
                        wizardApi.next();
                    }
                }
            );

            /**
             * Retry the oauth2 popup again.
             *
             * @name  retry
             * @scope
             */
            $scope.retry = function() {

                // Show OAUTH window
                var popup = oauth2PopupService.show($scope,
                    function onClose(reason) {
                        if (reason !== "closed") {
                            return;
                        }

                        // If the pop-up is closed before we get the code back, we should take
                        // them to the error page.
                        wizardApi.loadView("/authorize-customer-portal/error", null, {
                            replaceState: true
                        });
                    },
                    function onError(apiError) {
                        wizardApi.loadView("/authorize-customer-portal/error", null, {
                            replaceState: true
                        });
                    }
                );
                popup.focus();

                // Reload the instructions and information about the authorization process.
                wizardApi.loadView("/authorize-customer-portal/authorizing", null, {
                    clearAlerts: true,
                    replaceState: true
                });
            };

            /**
             * Cancel the whole wizard and go back to the start.
             *
             * @name  cancel
             * @scope
             */
            $scope.cancel = function() {
                wizardApi.loadView("/start", null, {
                    clearAlerts: true,
                    replaceState: true
                });
                wizardApi.reset(true);
            };

            /**
             * This gets the appropriate URL for creating a particular type of ticket.
             *
             * @method getTicketUrl
             * @type {String}     The type of ticket being created
             * @return {String}   The URL for creating that type of ticket
             */
            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

        }
    ]);
});
