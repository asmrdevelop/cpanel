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
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/inet6",
        "shared/js/email_deliverability/services/domains",
        "cjt/directives/copyField",
        "shared/js/email_deliverability/directives/suggestedRecordSet",
        "cjt/modules",
        "cjt/directives/callout",
        "cjt/directives/actionButtonDirective",
    ],
    function(angular, _, CJT, LOCALE, INET6, DomainsService, CopyField, SuggestedRecordSet) {

        "use strict";

        /**
         * Controller for Managing a Domain
         *
         * @module ManageDomainController
         * @memberof cpanel.emailDeliverability
         *
         */

        var MODULE_NAMESPACE = "shared.emailDeliverability.views.manageDomain";
        var MODULE_REQUIREMENTS = [
            DomainsService.namespace,
            CopyField.namespace,
            SuggestedRecordSet.namespace
        ];
        var CONTROLLER_NAME = "ManageDomainController";
        var CONTROLLER_INJECTABLES = ["$scope", "$location", "$routeParams", "DomainsService", "alertService", "ADD_RESOURCE_PANEL", "PAGE"];

        function formatRecordError(domain, recordType, error) {
            return LOCALE.maketext( "The system failed to complete validation of “[_1]”’s “[_2]” because of an error: [_3]", domain, recordType, error);
        }

        var CONTROLLER = function($scope, $location, $routeParams, $domainsService, $alertService, ADD_RESOURCE_PANEL, PAGE) {

            $scope.canReturnToLister = !PAGE.CAN_SKIP_LISTER || $domainsService.getAll().length > 1;

            $scope._returnToLister = function() {
                $location.path("/").search("");
            };

            /**
             *
             * Init the view
             *
             */
            $scope.init = function init() {

                var domains = $domainsService.getAll();

                $scope.currentDomain = $domainsService.findDomainByName($routeParams["domain"]);
                $scope.skipPTRLookups = PAGE.skipPTRLookups !== undefined ? PAGE.skipPTRLookups : false;

                if (!$scope.currentDomain && domains.length > 1) {
                    $alertService.add({
                        "message": LOCALE.maketext("You did not specify a domain to manage."),
                        "type": "info"
                    });

                    $scope._returnToLister();
                    return;
                } else if (domains.length === 1) {
                    $scope.currentDomain = domains[0];
                }

                angular.extend($scope, {
                    isWhm: CJT.isWhm(),
                    confirmDKIMDownloadRequest: false,
                    showConfirmDKIM: false,
                    dkimPrivateKey: false,
                    ptrServerName: "",
                    resourcesPanelTemplate: ADD_RESOURCE_PANEL,
                    isRecordValid: $scope.currentDomain.isRecordValid.bind($scope.currentDomain),
                    getSuggestedRecord: $scope.currentDomain.getSuggestedRecord.bind($scope.currentDomain),
                    errors: {}
                });

                var promise = $domainsService.validateAllRecords([$scope.currentDomain]).then($scope._handleRecordErrors);
                if (!$scope.skipPTRLookups) {
                    promise.then($scope._populatePTRInfo).then( $scope._handlePTRStatus );
                }
                return promise;
            };

            $scope._populatePTRInfo = function _populatePTRInformation() {
                var ptrDetails = $scope.currentDomain.getRecordDetails("ptr");
                var suggestedRecord = $scope.currentDomain.getSuggestedRecord("ptr");
                suggestedRecord.value = ptrDetails.helo + ".";
                $scope.currentDomain.setSuggestedRecord("ptr", suggestedRecord);

                $scope.ptrServerName = ptrDetails.helo;
                $scope.ptrServerIP = ptrDetails.ip_address;
            };

            /**
             *
             * Determine if current domain has nameserver authority
             *
             * @returns {Boolean} nameserver authority status
             */
            $scope.hasNSAuthority = function hasNSAuthority() {
                return $scope.currentDomain.hasNSAuthority;
            };

            /**
             *
             * Return the string message for a bad configuration
             *
             * @param {String} recordType record type to generate the message for
             * @returns {String} bad configuration message
             */
            $scope.badConfigurationMessage = function badConfigurationMessage(recordType) {
                var currentRecords = $scope.currentDomain.getRecords([recordType]);
                if (currentRecords.length) {
                    return LOCALE.maketext("“[_1]” is [output,strong,not] properly configured for this domain.", recordType.toUpperCase());
                } else {
                    return LOCALE.maketext("A “[_1]” record does [output,strong,not] exist for this domain.", recordType.toUpperCase());
                }
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
             * Generate a string message for a valid record
             *
             * @param {String} recordType record type to generate the message for
             * @returns {String} valid record message
             */
            $scope.validRecordMessage = function validRecordMessage(recordType) {
                return LOCALE.maketext("“[_1]” is properly configured for this domain.", recordType.toUpperCase());
            };

            /**
             *
             * Repair a record for the current domain
             *
             * @param {String} recordType record type to repair
             * @returns {Promise} repair record promise
             */
            $scope.repairRecord = function repairRecord(recordType) {
                var newRecord = $scope.getSuggestedRecord(recordType);
                var promise = $domainsService.repairDomain($scope.currentDomain, [recordType], [newRecord.value]);

                // Do this manually if no ns authority because the service does not
                if (!$scope.currentDomain.hasNSAuthority) {
                    promise.then($domainsService.validateAllRecords([$scope.currentDomain]));
                }
                if (!$scope.skipPTRLookups) {
                    promise.then($scope._populatePTRInfo);
                }
                promise.finally(function() {
                    if (!$scope.currentDomain.hasNSAuthority) {
                        $domainsService.unreflectedChangeMessage($scope.currentDomain.domain);
                    }
                    $scope.showConfirmDKIM = false;
                });
                return promise;
            };

            /**
             *
             * Toggle the visible state of the confirm DKIM installation message
             *
             */
            $scope.toggleShowConfirmDKIM = function toggleShowConfirmDKIM() {
                $scope.showConfirmDKIM = !$scope.showConfirmDKIM;
            };

            /**
             *
             * Get the current record for the current domain
             *
             * @param {String} recordType record type to get the current record for the domain
             * @returns {String} current record or empty string
             */
            $scope.getCurrentRecord = function getCurrentRecord(recordType) {
                return $domainsService.getCurrentRecord($scope.currentDomain, recordType);
            };

            $scope._handleRecordErrors = function _handleRecordErrors() {

                var allDetails = $scope.currentDomain.getRecordDetails();

                Object.keys(allDetails).forEach(function(recordType) {

                    var record = allDetails[recordType];

                    if ( record.error ) {
                        $scope.errors[recordType] = formatRecordError( $scope.currentDomain.domain, recordType.toUpperCase(), record.error );
                    }

                });

            };

            /**
             *
             * Get the ptr message based on the status of the invalid ptr record
             *
             * @returns {String} string message regarding PTR
             */
            $scope._handlePTRStatus = function _handlePTRStatus() {
                var details = $scope.currentDomain.getRecordDetails("ptr");

                var ptrState = details.state;
                var ptrRecords = details.ptr_records;
                var mailIP = details.ip_address;
                var mailHelo = details.helo;
                var ptrName = details.arpa_domain;

                $scope.ptrStatusCode = ptrState;

                if (ptrState === "IP_IS_PRIVATE") {
                    $scope.ipIsPrivate = true;
                } else {
                    var recordName = $scope.getSuggestedRecord("ptr").name;
                    recordName = recordName.replace(/\.$/, "");
                    $scope.ptrRecordName = _.escape(recordName);

                    var ptrNameservers = details.nameservers.map(_.escape) || [];
                    ptrNameservers.sort();

                    if (ptrState === "MISSING_PTR") {
                        $scope.badPTRMessages = [ LOCALE.maketext("There is no reverse [asis,DNS] configured for the [asis,IP] address ([_1]) that the system uses to send this domain’s outgoing email.", mailIP) ];

                        if (CJT.isWhm()) {
                            if (ptrNameservers.length) {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, create the following [asis,PTR] record at [list_and_quoted,_1]:", ptrNameservers);
                            } else {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, create the following [asis,PTR] record in [asis,DNS]:");
                            }
                        } else {
                            if (ptrNameservers.length) {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, contact your system administrator and request that they create the following [asis,PTR] record at [list_and_quoted,_1]:", ptrNameservers);
                            } else {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, contact your system administrator and request that they create the following [asis,PTR] record in [asis,DNS]:");
                            }
                        }
                    }

                    // At least one PTR value isn’t the expected value.
                    if (ptrState === "HELO_MISMATCH") {
                        var badNames = ptrRecords.filter( function(r) {
                            return (r.domain !== mailHelo);
                        } ).map( function(r) {
                            return r.domain;
                        } );

                        var resolvesSentence = LOCALE.maketext("The system sends “[_1]”’s outgoing email from the “[_2]” [output,abbr,IP,Internet Protocol] address.", $scope.currentDomain.domain, mailIP);

                        $scope.badPTRMessages = [
                            resolvesSentence + " " + LOCALE.maketext("The only [asis,PTR] value for this [output,abbr,IP,Internet Protocol] address must be “[_1]”. This is the name that this server sends with [output,abbr,SMTP,Simple Mail Transfer Protocol]’s “[_2]” command to send “[_3]”’s outgoing email.", mailHelo, "HELO", $scope.currentDomain.domain ),
                            LOCALE.maketext("[numf,_1] unexpected [asis,PTR] [numerate,_1,value exists,values exist] for this [output,abbr,IP,Internet Protocol] address:", badNames.length),
                        ];

                        $scope.badPTRNames = badNames;

                        if (CJT.isWhm()) {
                            if (ptrNameservers.length) {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, replace all [asis,PTR] records for “[_1]” with the following record at [list_and_quoted,_2]:", ptrName, ptrNameservers);
                            } else {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, replace all [asis,PTR] records for “[_1]” with the following record:", ptrName);
                            }
                        } else {
                            if (ptrNameservers.length) {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, contact your system administrator and request that they replace all [asis,PTR] records for “[_1]” with the following record at [list_and_quoted,_2]:", ptrName, ptrNameservers);
                            } else {
                                $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, contact your system administrator and request that they replace all [asis,PTR] records for “[_1]” with the following record:", ptrName);
                            }
                        }
                    }

                    // All PTRs are the expected value, but either there
                    // are no forward IPs or they all mismatch the mail IP.
                    //
                    // TODO: Because the PTR has the correct value, it’s
                    // probably more sensible to report this as a HELO
                    // problem than as a reverse DNS problem.
                    if (ptrState === "PTR_MISMATCH") {
                        var ips = ptrRecords[0].forward_records;

                        var badmsg = LOCALE.maketext("The system sends the domain “[_1]” in the [output,abbr,SMTP,Simple Mail Transfer Protocol] handshake for this domain’s email.", mailHelo);

                        if (!ips.length) {
                            badmsg += " " + LOCALE.maketext("“[_1]” does not resolve to any [output,abbr,IP,Internet Protocol] addresses.", mailHelo);
                        } else {
                            badmsg += " " + LOCALE.maketext("“[_1]” resolves to [list_and_quoted,_2], not “[_3]”.", mailHelo, ips, mailIP);
                        }

                        $scope.badPTRMessages = [badmsg];

                        var recordType = INET6.isValid(mailIP) ? "AAAA" : "A";

                        if (CJT.isWhm()) {
                            $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, create a [output,abbr,DNS,Domain Name System] “[_1]” record for “[_2]” whose value is “[_3]”.", recordType, mailHelo, mailIP);
                        } else {
                            $scope.ptrToFixMessage = LOCALE.maketext("To fix this problem, contact your system administrator and request that they create a [output,abbr,DNS,Domain Name System] “[_1]” record for “[_2]” whose value is “[_3]”.", recordType, mailHelo, mailIP);
                        }
                    }
                }
            };

            $scope.localDKIMExists = function() {
                return $domainsService.localDKIMExists($scope.currentDomain);
            };

            $scope.ensureLocalDKIMKeyExists = function() {
                return $domainsService.ensureLocalDKIMKeyExists($scope.currentDomain).then( $scope._handleRecordErrors );
            };

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
