/*
# email_deliverability/directives/domainListerViewDirective.js         Copyright 2022 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "shared/js/email_deliverability/directives/recordStatus",
        "shared/js/email_deliverability/filters/htmlSafeString",
        "shared/js/email_deliverability/services/domains"
    ],
    function(angular, _, CJT, LOCALE, RecordStatusDirective, SafeStringFilter, DomainsService) {

        "use strict";

        /**
         * Domain Lister View is a view that pairs with the item lister to
         * display domains and docroots as well as a manage link. It must
         * be nested within an item lister
         *
         * @module domain-lister-view
         * @restrict EA
         * @memberof cpanel.emailDeliverability
         *
         * @example
         * <item-lister>
         *     <domain-lister-view></domain-lister-view>
         * </item-lister>
         *
         */

        var MODULE_NAMESPACE = "cpanel.emailDeliverabilitty.domainListerView.directive";
        var MODULE_REQUIREMENTS = [ RecordStatusDirective.namespace, DomainsService.namespace, SafeStringFilter.namespace ];

        var RELATIVE_PATH = "shared/js/email_deliverability/directives/edDomainListerViewDirective.ptt";
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : CJT.buildPath(RELATIVE_PATH);
        var CONTROLLER_INJECTABLES = ["$scope", "DomainsService", "ITEM_LISTER_CONSTANTS", "DOMAIN_TYPE_CONSTANTS", "PAGE"];
        var CONTROLLER = function DomainListViewController($scope, $domainsService, ITEM_LISTER_CONSTANTS, DOMAIN_TYPE_CONSTANTS, PAGE) {

            $scope.DOMAIN_TYPE_CONSTANTS = DOMAIN_TYPE_CONSTANTS;
            $scope.EMAIL_ACCOUNTS_APP_EXISTS = PAGE.EMAIL_ACCOUNTS_APP_EXISTS;
            $scope.webserverRoleAvailable = PAGE.hasWebServerRole;
            $scope.recordsToCheck = $domainsService.getSupportedRecordTypes();

            $scope._confirmingRepairDomains = {};

            /**
             * Get the list of domains
             *
             * @method getDomains
             *
             * @public
             *
             * @return {Array<Domain>} returns an array of Domain objects
             *
             */

            $scope.getDomains = function getDomains() {
                return $scope.domains;
            };

            $scope.escapeString = _.escape;

            /**
             *
             * Get the row class based on the records status for the domain
             *
             * @param {Domain} domain domain object to obtain the status from
             * @returns {String|Boolean} will return the status if applicable, or false if not
             */
            $scope.getDomainRowClasses = function getDomainRowClasses(domain) {
                if (domain.recordsLoaded) {
                    if ( domain.hadAnyNSErrors ) {
                        domain._rowClasses = "danger";
                    } else if (!domain.recordsValid) {
                        domain._rowClasses = "warning";
                    } else {
                        return false;
                    }
                }
                return domain._rowClasses;
            };

            /**
             *
             * Determine if a message should be shown that record types are filtered
             *
             * @param {Domain} domain Object to determine the status of
             * @returns {Boolean} value of whether some records are filtered from view
             */
            $scope.showRecordsFilteredMessage = function showRecordsFilteredMessage(domain) {
                if (!domain.recordsLoaded) {
                    return false;
                }
                if (!domain.recordsValid) {
                    return false;
                }
                var loadedRecords = domain.getRecordTypesLoaded();
                var supportedRecords = $domainsService.getSupportedRecordTypes();
                return loadedRecords.length !== supportedRecords.length;
            };

            /**
             *
             * Show the "Confirm Repair" dialog
             *
             * @param {Domain} domain Subject to display the dialog for
             */
            $scope.confirmRepair = function confirmRepair(domain) {
                $scope._confirmingRepairDomains[domain.domain] = true;
            };

            /**
             *
             * Cancel displaying the confirm repair dialog
             *
             * @param {Domain} domain Subject to cancel the dialog for
             */
            $scope.cancelConfirmRepair = function cancelConfirmRepair(domain) {
                $scope._confirmingRepairDomains[domain.domain] = false;
            };

            /**
             *
             * Determine if the Confirm Repair dialog is shown
             *
             * @param {Domain} domain Subject to check the status of the confirm dialog for
             * @returns {Boolean} is the dialog shown
             */
            $scope.isConfirmingRepair = function isConfirmingRepair(domain) {
                return $scope._confirmingRepairDomains[domain.domain];
            };

            function _getZoneLockDomain(domain) {
                var zoneObj = $domainsService.getDomainZoneObject(domain);
                return zoneObj && zoneObj.getLockDomain();
            }

            $scope.getDomainLockedMessage = function getDomainLockedMessage(domain) {

                if (domain.recordsLoaded && !domain.hasNSAuthority) {

                    // Not authoritative, return relevant message
                    if (domain.nameservers.length) {
                        return LOCALE.maketext("This system does not control [asis,DNS] for the “[_1]” domain. Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the records.", domain.domain, domain.nameservers.length, domain.nameservers);
                    }

                    return LOCALE.maketext("This system does not control [asis,DNS] for the “[_1]” domain, and the system did not find any authoritative nameservers for this domain. Contact your domain registrar to verify this domain’s registration.", domain.domain);
                }

                if (!domain.recordsLoadingIn && _getZoneLockDomain(domain)) {

                    // Locked while updates are occuring, return relevant message

                    return LOCALE.maketext("You cannot modify this domain while a domain on the “[_1]” zone is updating.", domain.zone);
                }

                return false;

            };

            /**
             *
             * String to describe why this domain be auto-repaired.
             *
             * @param {Domain} domain Subject of the auto-repair inquiry
             * @returns {String} Localized description of why auto-repair isn’t possible, or undefined if auto-repair is indeed possible.
             */
            $scope.whyCannotAutoRepairDomain = function whyCannotAutoRepairDomain(domain) {
                var msg;

                if (!domain.recordsLoaded) {
                    msg = LOCALE.maketext("Loading …");
                } else if (!domain.hasNSAuthority) {
                    msg = LOCALE.maketext("Automatic repair is not available for this domain because this system is not authoritative for this domain.");
                } else {
                    var lockDomain = _getZoneLockDomain(domain);

                    if ( lockDomain ) {
                        msg = LOCALE.maketext("Automatic repair is currently unavailable for this domain. You must wait until “[_1]”’s operation completes because these two domains share the same DNS zone.", lockDomain);
                    } else if ( domain.isRecordValid("spf") && domain.isRecordValid("dkim") ) {
                        msg = LOCALE.maketext("This domain’s DKIM and SPF configurations are valid.");
                    }
                }

                return msg;
            };

            /**
             * dispatches a TABLE_ITEM_BUTTON_EVENT event
             *
             * @method actionButtonClicked
             *
             * @public
             *
             * @param  {String} type type of action taken
             * @param  {String} domain the domain on which the action occurred
             *
             * @return {Boolean} returns the result of the $scope.$emit function
             *
             */
            $scope.actionButtonClicked = function actionButtonClicked(type, domain) {
                return $scope.$emit(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, { actionType: type, item: domain, interactionID: domain.domain });
            };

            var recordTypeOrder = ["dkim", "spf", "ptr"];

            function _getSortedRecordLabel(recordsWithIssue) {

                if (recordsWithIssue.length === 0) {
                    return false;
                }

                recordsWithIssue.sort( function(a, b) {
                    a = recordTypeOrder.indexOf(a);
                    b = recordTypeOrder.indexOf(b);

                    return ( a < b ? -1 : a > b ? 1 : 0 );
                } );

                recordsWithIssue = recordsWithIssue.map(function(record) {
                    record = record.toUpperCase();

                    if (record === "PTR") {
                        return LOCALE.maketext("Reverse [asis,DNS]");
                    }

                    return record.toUpperCase();
                });

                return LOCALE.list_and(recordsWithIssue);
            }

            /**
             *
             * Get a list of record types with issues
             *
             * @param {Domain} domain Subject of inquiry
             * @returns {Array<String>} list of record types with issues
             */
            $scope.getRecordTypesWithIssues = function getRecordTypesWithIssues(domain) {
                return _getSortedRecordLabel( domain.getRecordTypesWithIssues() );
            };

            /**
             * Get a list of record types with DNS lookup errors
             *
             * @param {Domain} domain Subject of inquiry
             * @returs {Array<String>} list of record types with DNS lookup errors
             */
            $scope.getRecordTypesWithNSErrors = function getRecordTypesWithNSErrors(domain) {
                return _getSortedRecordLabel( domain.getRecordTypesWithNSErrors() );
            };

            $scope.localDKIMExists = function(domain) {
                return $domainsService.localDKIMExists(domain);
            };

            $scope.ensureLocalDKIMKeyExists = function(domain) {
                return $domainsService.ensureLocalDKIMKeyExists(domain);
            };

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        module.value("PAGE", PAGE);

        var DIRECTIVE_LINK = function($scope, $element, $attrs, $ctrl) {
            $scope.domains = [];
            $scope.headerItems = $ctrl.getHeaderItems();
            $scope.updateView = function updateView(viewData) {
                $scope.domains = viewData;
            };
            $ctrl.registerViewCallback($scope.updateView.bind($scope));

            $scope.$on("$destroy", function() {
                $ctrl.deregisterViewCallback($scope.updateView);
            });
        };
        module.directive("domainListerView", function itemListerItem() {

            return {
                templateUrl: TEMPLATE_PATH,

                restrict: "EA",
                replace: true,
                require: "^itemLister",
                link: DIRECTIVE_LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)

            };

        });

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "link": DIRECTIVE_LINK,
            "template": TEMPLATE_PATH
        };
    }
);
