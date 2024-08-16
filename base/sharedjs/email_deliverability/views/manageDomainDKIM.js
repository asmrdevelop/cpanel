/*
# email_deliverability/controller/manageDomainDKIM.js    Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "shared/js/email_deliverability/services/domains",
        "cjt/directives/copyField",
        "cjt/modules",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/directives/callout",
        "cjt/directives/multiFieldEditorItem",
        "cjt/directives/multiFieldEditor",
        "cjt/directives/actionButtonDirective",
    ],
    function(angular, _, LOCALE, DomainsService, CopyField) {

        "use strict";

        /**
         * Controller for Managing a Domain
         *
         * @module ManageDomainController
         * @memberof cpanel.emailDeliverability
         *
         */

        var MODULE_NAMESPACE = "shared.emailDeliverability.views.manageDomainDKIM";
        var MODULE_REQUIREMENTS = [
            DomainsService.namespace,
            CopyField.namespace
        ];
        var CONTROLLER_NAME = "ManageDomainDKIMController";
        var CONTROLLER_INJECTABLES = ["$scope", "$location", "$routeParams", "DomainsService", "alertService", "componentSettingSaverService", "ADD_RESOURCE_PANEL"];

        var CONTROLLER = function($scope, $location, $routeParams, $domainsService, $alertService, $CSSS, ADD_RESOURCE_PANEL) {

            /**
             *
             * Update the scope with the working domain records
             *
             */
            $scope.getWorkingRecords = function getWorkingRecords() {
                $scope.suggestedRecord = $scope.currentDomain.getSuggestedRecord("spf");
                $scope.workingRecord = $scope.suggestedRecord;

                var dkimRecords = $scope.currentDomain.getRecords(["dkim"]);
                $scope.currentRecord = dkimRecords[0] ? dkimRecords[0].current : "";
            };

            /**
             *
             * Initate the view
             *
             */
            $scope.init = function init() {
                var domains = $domainsService.getAll();

                if (!$scope.currentDomain && domains.length > 1) {
                    $alertService.add({
                        "message": LOCALE.maketext("You did not specify a domain to manage."),
                        "type": "danger"
                    });

                    $location.path("/").search("");
                    return;
                } else if (domains.length === 1) {
                    $scope.currentDomain = domains[0];
                }

                $scope.getWorkingRecords();

                if (!$scope.suggestedRecord) {
                    $domainsService.validateAllRecords([$scope.currentDomain]).then($scope.getWorkingRecords);
                }


                $CSSS.get(CONTROLLER_NAME).then(function(response) {
                    if (typeof response !== "undefined" && response) {
                        $scope.showAllHelp = response.showAllHelp;
                    }
                });

                $CSSS.register(CONTROLLER_NAME);

                $scope.$on("$destroy", function() {
                    $CSSS.unregister(CONTROLLER_NAME);
                });

            };

            /**
             *
             * Toggle the visible help for the form
             *
             */
            $scope.toggleHelp = function toggleHelp() {
                $scope.showAllHelp = !$scope.showAllHelp;
                $scope.$broadcast("showHideAllChange", $scope.showAllHelp);
            };

            /**
             *
             * Update the NVData saved aspects of this view
             *
             */
            $scope.saveToComponentSettings = function saveToComponentSettings() {
                $CSSS.set(CONTROLLER_NAME, {
                    showAllHelp: $scope.showAllHelp
                });
            };

            /**
             *
             * Verify if a user has nameserver authority for the current domain
             *
             * @returns {Boolean} representative of nameserver authority
             */
            $scope.hasNSAuthority = function hasNSAuthority() {
                return $scope.currentDomain.hasNSAuthority;
            };

            /**
             *
             * Toggle the Confirm Download DKIM message
             *
             */
            $scope.requestConfirmDownloadDKIMKey = function requestConfirmDownloadDKIMKey() {
                $scope.confirmDKIMDownloadRequest = true;
            };

            /**
             *
             * Post API Processing Function for confirmRevealDKIMKey
             *
             * @private
             *
             * @param {Object} dkimKeyObj API result DKIM Key Object {pem:...}
             */
            $scope._getPrivateDKIMKeyLoaded = function _getPrivateDKIMKeyLoaded(dkimKeyObj) {
                $scope.dkimPrivateKey = dkimKeyObj.pem;
            };

            /**
             *
             * Download the DKIM Key and display it
             *
             * @returns {Promise} fetchPrivateDKIMKey promise
             */
            $scope.confirmRevealDKIMKey = function confirmRevealDKIMKey() {
                return $domainsService.fetchPrivateDKIMKey($scope.currentDomain)
                    .then($scope._getPrivateDKIMKeyLoaded)
                    .finally($scope.cancelRevealDKIMKey);
            };

            /**
             *
             * Close teh DKIMKey Download Confirmation
             *
             */
            $scope.cancelRevealDKIMKey = function cancelRevealDKIMKey() {
                $scope.confirmDKIMDownloadRequest = false;
            };

            angular.extend($scope, {
                currentDomain: $domainsService.findDomainByName($routeParams["domain"]),
                resourcesPanelTemplate: ADD_RESOURCE_PANEL,
                showAllHelp: false,
                currentRecord: "",
                workingRecord: ""
            });

            $scope.init();

        };

        CONTROLLER_INJECTABLES.push(CONTROLLER);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES);

        return {
            class: CONTROLLER,
            namespace: MODULE_NAMESPACE
        };

    }
);
