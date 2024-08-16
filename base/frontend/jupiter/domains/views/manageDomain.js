/*
# domains/views/manageDomain.js                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/** @namespace cpanel.domains.views.manageDomain */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/modules",
        "cjt/directives/callout",
        "cjt/directives/actionButtonDirective",
        "app/services/domains",
    ],
    function(angular, _, LOCALE) {

        "use strict";

        var app = angular.module("cpanel.domains");

        /**
         * Create Controller for Domains
         *
         * @module manageDomain
         *
         * @param  {Object} $scope angular scope
         *
         */

        var controller = app.controller(
            "manageDomain",
            ["$scope", "$location", "$routeParams", "$q", "$timeout", "domains", "alertService", "DOMAIN_TYPE_CONSTANTS", "PAGE",
                function($scope, $location, $routeParams, $q, $timeout, $domainsService, $alertService, DOMAIN_TYPE_CONSTANTS, PAGE) {

                    function init() {
                        if (!$scope.currentDomain) {
                            $alertService.add({
                                "message": LOCALE.maketext("You did not specify a domain to manage."),
                                "type": "danger"
                            });

                            $location.path("/").search("");
                        }

                        $scope.showAdvancedDetailFields = false;
                        $scope.showSubdomainInDetails = $scope.currentDomain.type === DOMAIN_TYPE_CONSTANTS.ADDON;

                        if (DOMAIN_TYPE_CONSTANTS.SUBDOMAIN === $scope.currentDomain.type) {

                            // Current type is a subdomain, if it's associated with an addon domain
                            // we'd have to delete that domain instead.

                            $domainsService.get().then(function(domains) {
                                domains.forEach(function(domain) {
                                    if (domain.subdomain === $scope.currentDomain.subdomain && domain.type === DOMAIN_TYPE_CONSTANTS.ADDON) {
                                        $scope.associatedDomains.push(domain);
                                    }
                                });
                            });
                        }

                        $scope.canUpdateDocumentRoot = $scope.currentDomain.type !== DOMAIN_TYPE_CONSTANTS.ALIAS;

                        $scope.workingDomain = _generateWorkingDomain();
                    }

                    function _generateWorkingDomain() {
                        var workingDomain = angular.copy($scope.currentDomain);

                        // Perform witchcraft to ensure documentRoot is consistent
                        // requirePublicHTMLSubs and whatnot

                        // snip off the homedir and public_html
                        workingDomain.fullDocumentRoot = workingDomain.documentRoot;

                        var documentRoot = workingDomain.documentRoot;

                        var leadTrim = workingDomain.homedir;
                        if ($scope.requirePublicHTMLSubs) {
                            leadTrim += "/public_html";
                        }

                        if (documentRoot) {
                            var regexp = new RegExp("^" + _.escapeRegExp(leadTrim) + "(/)?");
                            documentRoot = documentRoot.replace(regexp, "");

                            workingDomain.documentRoot = documentRoot;
                        }

                        return workingDomain;
                    }

                    function getFormFieldClasses(form) {
                        return form && !form.$pristine && form.$invalid ? "col-xs-12 col-md-6" : "col-xs-12";
                    }


                    function update(form, domainObject) {

                        var alertID = "updating_" + domainObject.domain;

                        var fullDocumentRoot = $domainsService.generateFullDocumentRoot(domainObject.documentRoot);

                        if (!domainObject.rootDomain) {

                            // This domain is missing it's definition file, we should immediately error out
                            $alertService.add({
                                type: "danger",
                                id: alertID,
                                replace: true,
                                message: LOCALE.maketext("The domain userdata file for the “[_1]” domain appears to be missing.", domainObject.domain)
                            });
                            return;
                        }

                        function _updateSuccess() {
                            $alertService.add({
                                type: "success",
                                id: alertID,
                                replace: true,
                                message: LOCALE.maketext("You have successfully updated the document root to “[_1]” for the “[_2]” domain.", _.escape(fullDocumentRoot), domainObject.domain)
                            });

                            $scope.workingDomain = _generateWorkingDomain();
                        }

                        function _updateFailure() {
                            $alertService.removeById(alertID);
                        }

                        var promises = [];
                        if (!form.newDocumentRoot.$pristine) {
                            promises.push($domainsService.updateDocumentRoot(domainObject.domain, fullDocumentRoot).then(
                                _updateSuccess,
                                _updateFailure
                            ));
                        }

                        if (promises.length) {
                            return $q.all(promises);
                        }
                    }

                    function _showDeletionDelayedMessage() {
                        $scope.deletionDelayed = true;
                    }

                    function removeDomain() {

                        if (!$scope.currentDomain.rootDomain) {

                            // This domain is missing it's definition file, we should immediately error out
                            $alertService.add({
                                type: "danger",
                                replace: true,
                                message: LOCALE.maketext("The domain userdata file for the “[_1]” domain appears to be missing.", $scope.currentDomain.domain)
                            });
                            return;
                        }

                        var $timer = $timeout(_showDeletionDelayedMessage, 1000);

                        return $domainsService.remove($scope.currentDomain.domain).then(function() {
                            $alertService.add({
                                message: LOCALE.maketext("The system removed the “[_1]” domain and any associated redirections.", $scope.currentDomain.domain),
                                type: "success"
                            });

                            $location.path("/").search("");
                        }).finally(function() {
                            $scope.deletionDelayed = false;
                            $timeout.cancel($timer);
                        });

                    }

                    function startRemovalConfirmation() {
                        $scope.confirmingRemoval = true;
                    }
                    function cancelRemoval() {
                        $scope.confirmingRemoval = false;
                    }
                    function toggleAdvancedDetailFields() {
                        $scope.showAdvancedDetailFields = !$scope.showAdvancedDetailFields;
                    }

                    function deleteDependentDomainsError(domain, associatedDomains) {
                        return LOCALE.maketext("The system created the “[_1]” subdomain when it created the “[_2]” domain. To delete this subdomain, you must first delete the following [numerate,_3,domain,domains]:", domain, associatedDomains[0].domain, associatedDomains.length);
                    }

                    angular.extend($scope, {
                        associatedDomains: [],
                        deletionDelayed: false,
                        currentDomain: $domainsService.findDomainByName($routeParams["domain"]),
                        requirePublicHTMLSubs: PAGE.requirePublicHTMLSubs.toString() === "1",
                        webserverRoleAvailable: PAGE.hasWebServerRole,
                        mainDomain: $domainsService.getMainDomain(),
                        getFormFieldClasses: getFormFieldClasses,
                        documentRootPattern: $domainsService.getDocumentRootPattern(),
                        toggleAdvancedDetailFields: toggleAdvancedDetailFields,
                        update: update,
                        confirmingRemoval: false,
                        removeDomain: removeDomain,
                        startRemovalConfirmation: startRemovalConfirmation,
                        cancelRemoval: cancelRemoval,
                        deleteDependentDomainsError: deleteDependentDomainsError,
                    });

                    init();

                }
            ]
        );

        return controller;
    }
);
