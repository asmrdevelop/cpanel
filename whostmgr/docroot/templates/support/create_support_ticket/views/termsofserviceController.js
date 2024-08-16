/*
 * views/termsofserviceController.js               Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "cjt/util/locale",
    "cjt/directives/loadingPanel"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("termsofserviceController", [
        "$scope",
        "$q",
        "pageState",
        "wizardApi",
        "ticketService",
        "ticketUrlService",
        function(
            $scope,
            $q,
            pageState,
            wizardApi,
            ticketService,
            ticketUrlService
        ) {

            if (!wizardApi.verifyStep(/tos$/)) {
                return;
            }

            $scope.tos = {};

            $scope.uiState = {
                loading: false,
                failed: false
            };

            $scope.alertDetailsMessage = "";
            $scope.alertDetailsVisible = false;
            $scope.toggleMore = function(show) {
                if ($scope.alertDetailsMessage) {
                    $scope.alertDetailsVisible = show;
                } else {
                    $scope.alertDetailsVisible = false;
                }
            };

            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

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
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                wizardApi.reset();
                return false;
            };

            /**
             * Navigate to the next view.
             *
             * @name next
             * @scope
             */
            var next = function() {
                pageState.data.tos.accepted = true; // Accepted, but not yet saved
                wizardApi.loadView("/grant");
                return true;
            };


            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous,
                nextButtonText: LOCALE.maketext("Agree to Terms")
            });

            /**
             * Load the technical support agreement if its not
             * already loaded.
             *
             * @method  loadTechnicalSupportAgreement
             * @scope
             */
            $scope.loadTechnicalSupportAgreement = function() {

                /* If we've already loaded it once before, use the cached copy */
                if (pageState.tos) {
                    if (pageState.tos.accepted) {

                        // Get out as quick as possible, nothing further to do.
                        return $q.resolve();
                    }

                    $scope.tos = pageState.tos;
                    $scope.uiState = {
                        loading: false,
                        failed: false
                    };
                    return $q.resolve();
                }

                /* Otherwise, retrieve it via the API ... */

                $scope.uiState = {
                    loading: true,
                    failed: false
                };

                wizardApi.disableNextButton();

                return ticketService.fetchTechnicalSupportAgreement().then(function(result) {
                    $scope.tos = result.data;
                    wizardApi.enableNextButton();
                    $scope.uiState = {
                        loading: false,
                        failed: false
                    };
                })
                    .catch(function(error) {
                        $scope.uiState = {
                            loading: false,
                            failed: true
                        };
                        $scope.alertDetailsMessage = error;
                        return $q.reject(error);
                    });
            };

            $scope.loadTechnicalSupportAgreement().then(function() {
                if (pageState.tos.accepted) {

                    // We can skip further display of this step
                    wizardApi.loadView("/grant");
                    wizardApi.next();
                }
            });
        }
    ]);
});
