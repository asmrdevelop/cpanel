/*
 * views/supportInfoController.js                        Copyright(c) 2020 cPanel, L.L.C
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "angular",
    "cjt/util/locale",
    "cjt/directives/alert"
], function(
        angular,
        LOCALE
    ) {

    "use strict";
    var app = angular.module("whm.createSupportTicket");

    return app.controller("supportInfoController", [
        "$scope",
        "pageState",
        "wizardApi",
        "ticketService",
        function(
            $scope,
            pageState,
            wizardApi,
            ticketService
        ) {

            if (!wizardApi.verifyStep(/supportinfo$/)) {
                return;
            }

            $scope.supportinfo = {};
            $scope.uiState = {};

            $scope.uiState.loading = true;
            wizardApi.disableNextButton();

            /**
             * Goes to the next step in the wizard
             *
             * @method gotoNextStep
             */
            var gotoNextStep = function() {
                $scope.uiState.loading = false;
                wizardApi.enableNextButton();
                if ( pageState.tos && pageState.tos.accepted ) {
                    wizardApi.loadView("/grant", null, { clearAlerts: true });
                } else {
                    wizardApi.loadView("/tos", null, { clearAlerts: true });
                }
                return true;
            };

            /**
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                wizardApi.enableNextButton();
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
                gotoNextStep();
                return true;
            };

            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous
            });

            /**
             * Toggles the next button depending on the status of the checkbox.
             *
             * @method toggleNext
             */
            $scope.toggleNext = function() {
                if ( $scope.cpanelSupportWarning ) {
                    wizardApi.enableNextButton();
                } else {
                    wizardApi.disableNextButton();
                }
            };

            /**
             * Load the support information from the users license
             *
             * @method  loadSupportInformation
             * @scope
             */
            $scope.loadSupportInformation = function() {

                return ticketService.fetchSupportInfo().then(function(result) {
                    $scope.supportinfo = result.data;
                    $scope.uiState.loading = false;

                    // skip this step if the returned data does not have the information we are looking for.
                    if ( $scope.supportinfo.data.company_name === "" || $scope.supportinfo.data.pub_tech_contact === "" || $scope.supportinfo.data.pub_tech_contact.indexOf("tickets.cpanel.net") > -1 ) {
                        gotoNextStep();
                    }
                })
                    .catch(function(error) {

                        // If something fails, just skip this step and continue to the next.
                        return gotoNextStep();
                    });
            };

            // do the work!
            $scope.loadSupportInformation();
        }
    ]);
});
