/*
# domains/directives/domainListerViewDirective.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/** @namespace cpanel.domains.directives.domainListerView */

define(
    [
        "lodash",
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "app/directives/docrootDirective",
        "app/services/domains"
    ],
    function(_, angular, CJT, LOCALE) {

        "use strict";

        var module = angular.module("cpanel.domains.domainListerView.directive", [ "cpanel.domains.docroot.directive" ]);

        module.value("PAGE", PAGE);

        module.directive("domainListerView", function itemListerItem() {

            /**
             * Domain Lister View is a view that pairs with the item lister to
             * display domains and docroots as well as a manage link. It must
             * be nested within an item lister
             *
             * @module domain-lister-view
             * @restrict EA
             *
             * @example
             * <item-lister>
             *     <domain-lister-view></domain-lister-view>
             * </item-lister>
             *
             */

            var TEMPLATE_PATH = "directives/domainListerViewDirective.ptt";
            var RELATIVE_PATH = "domains/" + TEMPLATE_PATH;

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,

                restrict: "EA",
                replace: true,
                require: "^itemLister",
                link: function($scope, $element, $attrs, $ctrl) {
                    $scope.domains = [];
                    $scope.showConfigColumn = $ctrl.showConfigColumn;
                    $scope.headerItems = $ctrl.getHeaderItems();
                    $scope.updateView = function updateView(viewData) {
                        $scope.domains = viewData;
                    };

                    $scope.scope = $scope;
                    $ctrl.registerViewCallback($scope.updateView.bind($scope));

                    $scope.$on("$destroy", function() {
                        $ctrl.deregisterViewCallback($scope.updateView);
                    });
                },
                controller: ["$scope", "ITEM_LISTER_CONSTANTS", "DOMAIN_TYPE_CONSTANTS", "PAGE", "domains", "alertService", function($scope, ITEM_LISTER_CONSTANTS, DOMAIN_TYPE_CONSTANTS, PAGE, $domainServices, $alertService) {


                    $scope.isRTL = PAGE.isRTL;

                    $scope.DOMAIN_TYPE_CONSTANTS = DOMAIN_TYPE_CONSTANTS;
                    $scope.EMAIL_ACCOUNTS_APP_EXISTS = PAGE.EMAIL_ACCOUNTS_APP_EXISTS;
                    $scope.webserverRoleAvailable = PAGE.hasWebServerRole;
                    $scope.canRedirectHTTPS = $domainServices.canRedirectHTTPS();

                    $scope.getDomains = function getDomains() {

                        // Escape domains
                        for (var i = 0; i < $scope.domains.length; i++) {
                            $scope.domains[i].domain = _.escape($scope.domains[i].domain);
                            $scope.domains[i].homedir = _.escape($scope.domains[i].homedir);
                        }
                        return $scope.domains;
                    };

                    /**
                     * dispatches a TABLE_ITEM_BUTTON_EVENT event
                     *
                     * @method actionButtonClicked
                     *
                     * @param  {String} type type of action taken
                     * @param  {String} domain the domain on which the action occurred
                     *
                     * @return {Boolean} returns the result of the $scope.$emit function
                     *
                     */
                    $scope.actionButtonClicked = function actionButtonClicked(type, domain) {
                        $scope.$emit(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, { actionType: type, item: domain, interactionID: domain.domain });
                    };

                    $scope.itemSelected = function itemSelected(domain) {
                        $scope.$emit(ITEM_LISTER_CONSTANTS.ITEM_SELECT_EVENT, domain);
                    };

                    $scope.HTTPSRedirectWarning = LOCALE.maketext("You cannot activate [asis,HTTPS] Redirect because [asis,AutoSSL] is not currently active for this domain or the [asis,SSL] certificate is not valid.");
                    $scope.AliasRowWarning = LOCALE.maketext("Addon and parked domains inherit their [asis,HTTPS] redirect status from their associated subdomain.");
                    $scope.AliasWarning = LOCALE.maketext("Some aliases for this domain may not have a working SSL certificate configured.");

                    $scope.setSingleDomainHTTPSRedirect = function(domain) {
                        domain.isHttpsRedirecting = !domain.isHttpsRedirecting;
                        var successMessage, failureMessage;
                        if (domain.isHttpsRedirecting) {
                            successMessage = LOCALE.maketext("Force [asis,HTTPS] Redirect is enabled for the “[_1]” domain.", domain.domain);
                            failureMessage = LOCALE.maketext("The system failed to enable Force [asis,HTTPS] Redirect.");
                        } else {
                            successMessage = LOCALE.maketext("Force [asis,HTTPS] Redirect is disabled for the “[_1]” domain.", domain.domain);
                            failureMessage = LOCALE.maketext("The system failed to disable Force [asis,HTTPS] Redirect.");
                        }
                        $domainServices.toggleHTTPSRedirect(domain.isHttpsRedirecting, domain.domain)
                            .then(function(data) {
                                if (data.status) {

                                    // Change state of the link to the domain to properly reflect https status
                                    var theLink = document.getElementById(domain.domain + "_domain_link");
                                    if (typeof (theLink) !== "undefined") {
                                        var protocol = domain.isHttpsRedirecting ? "https" : "http";
                                        theLink.href = protocol + "://" + domain.domain;
                                    }

                                    $alertService.add({
                                        message: successMessage,
                                        type: "success",
                                        autoClose: 10000
                                    });
                                } else {
                                    $alertService.add({
                                        message: failureMessage,
                                        type: "danger"
                                    });
                                }
                            });
                    };
                }]
            };
        });
    }
);
