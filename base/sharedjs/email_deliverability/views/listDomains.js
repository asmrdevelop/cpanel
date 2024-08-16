/*
# email_deliverability/controllers/listDomains.js          Copyright 2022 cPanel, L.L.C.
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
        "shared/js/email_deliverability/directives/edDomainListerViewDirective",
        "shared/js/email_deliverability/directives/tableShowingDirective",
        "shared/js/email_deliverability/directives/itemLister",
        "shared/js/email_deliverability/services/domains",
        "cjt/modules"
    ],
    function(angular, _, LOCALE, DomainListerViewDirective, TableShowingDirective, ItemListerDirective, DomainsService) {

        "use strict";

        /**
         * Controller for Listing Domains
         *
         * @module ListDomainsController
         * @memberof cpanel.emailDeliverability
         *
         */

        /**
         * @class TableHeader
         * @memberof cpanel.emailDeliverability
         *
         * @property {String} field which field the column will sort by
         * @property {String} label Label descriptor of the column
         * @property {boolean} sortable is this column sortable
         */
        var TableHeader = function() {
            this.field = "";
            this.label = "";
            this.sortable = false;
        };

        /**
         * Factory to create a TableHeader
         *
         * @module TableHeaderFactory
         * @memberof cpanel.emailDeliverability
         *
         */
        function createTableHeader(field, sortable, label, description, hiddenOnMobile) {
            function _makeLabel() {
                if (!description) {
                    return label;
                }
                return label + " <span class='thead-desc'>" + description + "</span>";
            }
            var tableHeader = new TableHeader();
            tableHeader.field = field;
            tableHeader.label = _makeLabel();
            tableHeader.sortable = sortable;
            tableHeader.hiddenOnMobile = hiddenOnMobile;
            return tableHeader;
        }

        var MODULE_NAMESPACE = "shared.emailDeliverability.views.listDomains";
        var MODULE_REQUIREMENTS = [
            TableShowingDirective.namespace,
            ItemListerDirective.namespace,
            DomainListerViewDirective.namespace,
            DomainsService.namespace
        ];
        var CONTROLLER_NAME = "ListDomainsController";
        var CONTROLLER_INJECTABLES = ["$scope", "$timeout", "$location", "$log", "$q", "alertService", "DomainsService", "initialDomains", "ITEM_LISTER_CONSTANTS", "PAGE"];

        var CONTROLLER = function ListDomainsController($scope, $timeout, $location, $log, $q, $alertService, $domainsService, initialDomains, ITEM_LISTER_CONSTANTS, PAGE) {

            /**
             * Called when a ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT is $emit'd
             *
             * @method
             * @param {Object} event even object emitted
             * @param {Object} parameters parameters object emitted by the source
             *
             */
            $scope.itemChangeRequested = function _itemChangeRequested(event, parameters) {
                switch (parameters.actionType) {
                    case "manage":
                        $scope.manageDomain(parameters.item.domain);
                        break;
                    case "repair":
                        $scope.repairDomain(parameters.item.domain);
                        break;
                    case "repairAll":
                        $scope.repairAllDomainRecords(parameters.domain);
                        break;
                }
            };

            /**
             *
             * Function that when called moves the user to the manage view for a domain
             *
             * @public
             *
             * @param {String} domain string domain name
             */
            $scope.manageDomain = function _manageDomain(domain) {
                $domainsService.markViewLoad();
                $location.path("manage").search("domain", domain);
            };

            /**
             *
             * Get the suggested for a record type for a specific domain
             *
             * @public
             *
             * @param {Domain} domainObj domain from which to get the suggested record
             * @param {string} recordType type of record to fetch
             * @returns {String} string suggested record for the domain
             */
            $scope.getSuggestedRecord = function getSuggestedRecord(domainObj, recordType) {
                return domainObj.getSuggestedRecord(recordType);
            };

            /**
             *
             * Repair all repairable records for a specific domain
             *
             * @param {Domain} domain domain to repair
             * @returns {Promise} returns the repair promise
             */
            $scope.repairDomain = function repairDomain(domain) {

                var domainObj = $domainsService.findDomainByName(domain);
                $alertService.clear();

                var recordTypes = $scope.getDisplayedRecordTypes();
                recordTypes = recordTypes.filter(function(recordType) {
                    if (recordType !== "ptr" && !domainObj.isRecordValid(recordType)) {
                        return true;
                    }
                    return false;
                });

                var records = recordTypes.map(function(recordType) {
                    var newRecord = $scope.getSuggestedRecord(domainObj, recordType);
                    return newRecord.value;
                });

                return $domainsService.repairDomain(domain, recordTypes, records);
            };

            /**
             *
             * Get the record types that are not disabled in this view
             *
             * @returns {Array<String>} array of record types
             */
            $scope.getDisplayedRecordTypes = function getDisplayedRecordTypes() {
                return $domainsService.getSupportedRecordTypes();
            };


            /**
             *
             * Fetch the validation data for the displayed domains
             *
             * @private
             *
             * @param {Array<Domain>} domains array of domains to update
             * @returns {Promise} promise for the validateAllRecords call
             */
            $scope._fetchTableData = function _fetchTableData(domains) {
                var recordTypes = $scope.getDisplayedRecordTypes();
                return $domainsService.validateAllRecords(domains, recordTypes);
            };

            /**
             *
             * Debounce call for fetching domains (prevents doubling up of fetch calls)
             *
             * @private
             *
             */
            $scope._beginDelayedFetch = function _beginDelayedFetch() {
                if ($scope.currentTimeout) {
                    $timeout.cancel($scope.currentTimeout);
                    $scope.currentTimeout = null;
                }

                $scope.currentTimeout = $timeout($scope._fetchTableData, 500, true, $scope.pageDomains);
            };


            /**
             *
             * Event capture call for emitted ITEM_LISTER_CONSTANTS.ITEM_LISTER_UPDATED_EVENT events
             *
             * @private
             *
             * @param {Object} event event object
             * @param {Object} parameters event parameters {meta:{filterValue:...},items:...}
             */
            $scope._itemListerUpdated = function _itemListerUpdated(event, parameters) {

                $scope.itemListerMeta = parameters.meta;
                $scope.currentSearchFilterValue = $scope.itemListerMeta.filterValue;
                $scope.pageDomains = parameters.items;

                $scope._beginDelayedFetch();

            };


            /**
             *
             * Build the table headers for the lister
             *
             * @private
             *
             * @returns {Array<TableHeader>} array of table headers
             */
            $scope._buildTableHeaders = function _buildTableHeaders() {
                var tableHeaderItems = [];
                tableHeaderItems.push( createTableHeader( "domain", true, LOCALE.maketext("Domain"), false, false ) );
                tableHeaderItems.push( createTableHeader( "status", false, LOCALE.maketext("Email Deliverability Status"), false, true ) );
                tableHeaderItems.push( createTableHeader( "actions", false, "", false )  );
                return tableHeaderItems;
            };

            /**
             *
             * Get a list of filtered domains
             *
             * @returns {Array<Domain>} list of domains to display
             */
            $scope.getFilteredDomains = function getFilteredDomains() {
                return $scope.filteredDomains;
            };

            /**
             *
             * Function called upon completion of the CSSS load
             *
             * @private
             *
             */
            $scope._readyToDisplay = function _readyToDisplay() {
                $scope.$on(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, $scope.itemChangeRequested);
                $scope.$on(ITEM_LISTER_CONSTANTS.ITEM_LISTER_UPDATED_EVENT, $scope._itemListerUpdated);
            };

            /**
             *
             * Initate the view
             *
             */
            $scope.init = function init() {

                if (initialDomains.length === 1 && PAGE.CAN_SKIP_LISTER) {
                    $location.path("/manage").search("domain", initialDomains[0].domain);
                } else {
                    $scope.domains = initialDomains;
                    $scope.filteredDomains = initialDomains;
                    $scope.tableHeaderItems = $scope._buildTableHeaders();

                    $scope._readyToDisplay();
                }

            };

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
