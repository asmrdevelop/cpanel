/*
# email_deliverability/controller/manageDomain.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "shared/js/email_deliverability/services/domains",
        "shared/js/email_deliverability/services/spfParser",
        "shared/js/email_deliverability/services/SPFRecordProcessor",
        "cjt/directives/copyField",
        "cjt/modules",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/directives/callout",
        "cjt/directives/multiFieldEditorItem",
        "cjt/directives/multiFieldEditor",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/ip-validators",
        "cjt/validator/domain-validators",
    ],
    function(angular, _, LOCALE, DomainsService, SPFParser, SPFRecordProcessor, CopyField) {

        "use strict";

        /**
         * Controller for Managing a Domain
         *
         * @module ManageDomainController
         * @memberof cpanel.emailDeliverability
         *
         */

        var MODULE_NAMESPACE = "shared.emailDeliverability.views.manageDomainSPF";
        var MODULE_REQUIREMENTS = [
            DomainsService.namespace,
            CopyField.namespace
        ];
        var CONTROLLER_NAME = "ManageDomainSPFController";
        var CONTROLLER_INJECTABLES = ["$scope", "$log", "$location", "$routeParams", "DomainsService", "alertService", "componentSettingSaverService", "ADD_RESOURCE_PANEL"];

        var CONTROLLER = function($scope, $log, $location, $routeParams, $domainsService, $alertService, $CSSS, ADD_RESOURCE_PANEL) {

            var MECHANISM_ARRAYS = ["additionalHosts", "additionalMXServers", "additionalIPv4Addresses", "additionalIPv6Addresses", "additionalINCLUDEItems"];

            $scope._updateSuggestedRecords = function _updateSuggestedRecords() {
                $scope.suggestedRecord = $scope.currentDomain.getSuggestedRecord("spf");
                var originalExpected = $scope.suggestedRecord.originalExpected || "";
                var originalExpectedTerms = originalExpected.trim().split(/\s+/);
                $scope.missingMechanisms = originalExpectedTerms.map(SPFRecordProcessor._parseSPFTerm).filter(function(term) {
                    if ( !term.type ) {
                        return false;
                    }
                    return true;
                });

                $scope.workingRecord = $scope.suggestedRecord;

                $scope.populateFormFrom($scope.workingRecord);

                $scope.updatePreview();
            };

            /**
             *
             * Initiate the current view
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

                $CSSS.get(CONTROLLER_NAME).then(function(response) {
                    if (typeof response !== "undefined" && response) {
                        $scope.showAllHelp = response.showAllHelp;
                    }
                });

                $CSSS.register(CONTROLLER_NAME);

                $scope.$on("$destroy", function() {
                    $CSSS.unregister(CONTROLLER_NAME);
                });

                MECHANISM_ARRAYS.forEach(function(attr) {
                    $scope.$watchCollection(attr, $scope.updatePreview.bind($scope));
                });

                return $domainsService.validateAllRecords([$scope.currentDomain]).then($scope._updateSuggestedRecords).then(function() {
                    $scope._hasNSAuthority = $scope.currentDomain.hasNSAuthority;
                });

            };


            /**
             *
             * Parse SPF record into various mechanisms
             *
             * @param {String} record SPF record to parse
             */
            $scope.parseRecord = function parseRecord(record) {
                if (!record) {
                    return;
                }
                if (!record.value) {
                    return;
                }
                var currentRecordParts = SPFParser.parse(record.value);
                var mechanisms = currentRecordParts.mechanisms;
                mechanisms.forEach(function(mechanism) {
                    if (mechanism.type !== "all" && !mechanism.value) {
                        return;
                    }

                    if (["version", "all"].indexOf(mechanism.type) === -1 && mechanism.prefix !== "+") {
                        $log.debug("Non-pass mechanism exists. Presenting warning.", mechanism);
                        $scope.nonPassPrefixesExist = true;
                        return;
                    }

                    if (mechanism.type === "mx") {
                        $scope.additionalMXServers.push(mechanism.value);
                    } else if (mechanism.type === "ip4") {
                        $scope.additionalIPv4Addresses.push(mechanism.value);
                    } else if (mechanism.type === "ip6") {
                        $scope.additionalIPv6Addresses.push(mechanism.value);
                    } else if (mechanism.type === "all" && mechanism.prefix === "-") {
                        $scope.excludeAllOtherDomains = true;
                    } else if (mechanism.type === "a") {
                        $scope.additionalHosts.push(mechanism.value);
                    } else if (mechanism.type === "include") {
                        $scope.additionalINCLUDEItems.push(mechanism.value);
                    }
                });
            };

            /**
             *
             * Remove duplicates from each of the mechanism arrays
             *
             */
            $scope.removeDuplicates = function removeDuplicates() {

                MECHANISM_ARRAYS.forEach(function(MECH_AR) {

                    var original = $scope[MECH_AR].slice(0);
                    var uniq = _.uniq(original);

                    $scope[MECH_AR].splice(0, $scope[MECH_AR].length);

                    uniq.forEach($scope[MECH_AR].push);
                });
            };

            /**
             *
             * Populate form from passed records
             *
             * @param {String} record SPF record to populate form from
             */
            $scope.populateFormFrom = function populateFormFromRecords(record) {

                // Clear current values
                MECHANISM_ARRAYS.forEach(function(MECH_AR) {
                    $scope[MECH_AR].splice(0, $scope[MECH_AR].length);
                });

                $scope.parseRecord(record);
            };

            $scope.toggleExcludeAllOtherDomains = function toggleExcludeAllOtherDomains() {
                $scope.excludeAllOtherDomains = !$scope.excludeAllOtherDomains;
                $scope.updatePreview();
            };

            /**
             *
             * Update the $scope.workingPreview variable with the SPF Record
             *
             */
            $scope.updatePreview = function updatePreview() {

                // Build new user requested record.
                var newWorkingPreview = ["v=spf1", "+mx", "+a"];

                if (!$scope.missingMechanisms) {
                    return;
                }

                // add +a records
                $scope.additionalHosts.forEach(function(item) {
                    newWorkingPreview.push("+a:" + item);
                });

                // add +mx records
                $scope.additionalMXServers.forEach(function(item) {
                    newWorkingPreview.push("+mx:" + item);
                });

                // add all other ip4 addresses
                $scope.additionalIPv4Addresses.forEach(function(item) {
                    newWorkingPreview.push("+ip4:" + item);
                });

                // add all other ip6 addresses
                $scope.additionalIPv6Addresses.forEach(function(item) {
                    newWorkingPreview.push("+ip6:" + item);
                });

                // add all includes
                // these need to be last
                $scope.additionalINCLUDEItems.forEach(function(item) {
                    newWorkingPreview.push("+include:" + item);
                });

                // preserve non-pass mechanisms from current record
                // overridden ones will get collapsed away.
                var currentRecord = $scope.currentDomain.getCurrentRecord("spf");
                var currentRecordParts, mechanisms;
                if (currentRecord && currentRecord.value) {
                    currentRecordParts = SPFParser.parse(currentRecord.value);
                    mechanisms = currentRecordParts.mechanisms;
                    mechanisms.forEach(function(mechanism) {

                        if (["version", "all"].indexOf(mechanism.type) === -1 && mechanism.prefix !== "+") {

                            // non plus mechanisms
                            newWorkingPreview.push(mechanism.prefix + mechanism.type + ":" + mechanism.value);
                        }

                    });
                }

                // add ~all?
                if ($scope.excludeAllOtherDomains) {
                    newWorkingPreview.push("-all");
                } else {
                    newWorkingPreview.push("~all");
                }

                var newWorkingPreviewString = newWorkingPreview.join(" ");

                // v=spf1 +a +mx +ip4:10.215.218.115 +a:aaaaaaaaaa.com +mx:mxxxxxx.com +ip4:192.168.1.1 +include:include.com -all
                $scope.workingRecord = SPFRecordProcessor.combineRecords(newWorkingPreviewString, $scope.missingMechanisms);
            };

            /**
             *
             * Determine if current domain has nameserver authority
             *
             * @returns {Boolean} nameserver authority status
             */
            $scope.hasNSAuthority = function hasNSAuthority() {
                return $scope._hasNSAuthority;
            };

            /**
             *
             * Return the string message for a bad configuration
             *
             * @param {String} recordType record type to generate the message for
             * @returns {String} bad configuration message
             */
            $scope.badConfigurationMessage = function badConfigurationMessage(recordType) {
                return LOCALE.maketext("“[_1]” is [output,strong,not] properly configured for this domain.", recordType.toUpperCase());
            };

            /**
             *
             * Generate the string message for a user with no authority
             *
             * @param {String} recordType record type to generate the message for
             * @returns {String} the no authority message
             */
            $scope.noAuthorityMessage = function noAuthorityMessage(recordType) {
                return $domainsService.getNoAuthorityMessage($scope.currentDomain, recordType);
            };

            /**
             *
             * Toggle the visible help for the form
             *
             */
            $scope.toggleHelp = function toggleHelp() {
                $scope.showAllHelp = !$scope.showAllHelp;
                $scope.saveToComponentSettings();
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
             * Repair the SPF record for the current domain
             *
             * @returns {Promise} repairRecord promise
             */
            $scope.update = function update() {
                return $domainsService.repairDomain($scope.currentDomain, ["spf"], [$scope.workingRecord], !$scope.hasNSAuthority())
                    .then(function() {

                        // Do this manually if no ns authority because the service does not
                        if (!$scope.hasNSAuthority()) {
                            return $domainsService.validateAllRecords([$scope.currentDomain]).then($scope._updateSuggestedRecords);
                        }
                    })
                    .finally(function() {
                        if (!$scope.hasNSAuthority()) {
                            $domainsService.unreflectedChangeMessage($scope.currentDomain.domain);
                        }
                        $scope.showConfirmDKIM = false;
                    });
            };

            $scope.currentDomain = $domainsService.findDomainByName($routeParams["domain"]);

            angular.extend($scope, {
                getCurrentRecord: $scope.currentDomain.getCurrentRecord.bind($scope.currentDomain),
                resourcesPanelTemplate: ADD_RESOURCE_PANEL,
                showAllHelp: false,
                currentRecord: "",
                workingRecord: "",

                /* form fields */
                excludeAllOtherDomains: false,
                additionalHosts: [],
                additionalMXServers: [],
                additionalIPv4Addresses: [],
                additionalIPv6Addresses: [],
                additionalINCLUDEItems: []
            });

            return $scope.init();

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
