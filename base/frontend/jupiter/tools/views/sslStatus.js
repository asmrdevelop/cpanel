/*
 * tools/views/sslStatus.js                                Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/modules",
        "cjt/services/cpanel/SSLStatus",
        "uiBootstrap",
    ],
    function(angular, LOCALE, modules, SSLStatus) {

        "use strict";

        var MODULE_NAMESPACE = "cpanel.tools.views.sslStatus";
        var MODULE_DEPENDANCIES = [
            "cjt2.cpanel",
            SSLStatus.namespace,
        ];

        var CONTROLLER_NAME = "sslStatusController";
        var CONTROLLER_INJECTABLES = ["$scope", SSLStatus.serviceName, "$timeout"];

        var CONTROLLER = function SSLStatusController($scope, $service, $timeout) {

            $scope.sslStatusString = null;
            $scope.sslStatusLoaded = false;
            $scope.sslValidationIconClasses = "fas fa-spinner fa-spin";
            $scope.statusColorClasses = "";
            $scope.certErrorsMessage = "";
            $scope.domainLink = "#";

            $scope._setSSLCertificate = function _setSSLCertificate(sslCertificate) {
                $scope.sslStatusLoaded = true;
                $scope.sslStatusString = sslCertificate.getTypeName();
                $scope.expandedSslStatusString = sslCertificate.getTypeName({ stripMarkup: true });
                $scope.sslValidationIconClasses = sslCertificate.getIconClasses() === "fas fa-unlock-alt" ? "ri-lock-unlock-line" : "ri-lock-line";
                $scope.statusColorClasses = sslCertificate.getStatusColorClass();
                $scope.sslSecured = $scope.statusColorClasses !== "text-danger";
                $scope.certHasErrors = sslCertificate.hasErrors;
                $scope.certErrorsMessage = LOCALE.maketext("The certificate has the following errors: [list_and,_1]", sslCertificate.getErrors());

                // since a cert is always returned, if it has any kind of validation type, display it as ssl
                $scope.domainLink = sslCertificate.validationType ? "https://" + $scope.primaryDomain : "http://" + $scope.primaryDomain;
            };

            $scope._domainNotSet = function _domainNotSet() {
                throw "primaryDomain must be set on init";
            };

            // return this for testing
            return $timeout(function() {
                if (!$scope.primaryDomain) {
                    $scope._domainNotSet();
                    return;
                }
                $scope.domainLink = "http://" + $scope.primaryDomain;
                return $service.getDomainSSLCertificate($scope.primaryDomain, true).then($scope._setSSLCertificate.bind($scope));
            }, 1);

        };

        CONTROLLER_INJECTABLES.push(CONTROLLER);

        var app = angular.module(MODULE_NAMESPACE, MODULE_DEPENDANCIES);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES);

        return {
            "controller": CONTROLLER_NAME,
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
        };
    }
);
