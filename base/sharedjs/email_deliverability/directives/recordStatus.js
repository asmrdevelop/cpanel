/*
# email_deliverability/directives/recordStatus.js              Copyright 2022 cPanel, L.L.C.
#                                                                        All rights reserved.
# copyright@cpanel.net                                                      http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        /**
         * Record Status
         *
         * @module record-status
         * @restrict EA
         *
         * @memberof cpanel.emailDeliverability
         *
         * @example
         * <td record-status
         *  domain="{domain:'domain.com'}"
         *  header="{field: 'headerField' label: 'Header'}" ></td>
         *
         */

        var RELATIVE_PATH = "shared/js/email_deliverability/directives/recordStatus.phtml";
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : CJT.buildPath(RELATIVE_PATH);
        var MODULE_NAMESPACE = "cpanel.emailDeliverabilitty.recordStatus.directive";
        var MODULE_REQUIREMENTS = [];

        var CONTROLLER_INJECTABLES = ["$scope"];
        var CONTROLLER = function RecordStatusController($scope) {

            /**
             * Generates a status icon class based on record validity
             *
             * @method _getStatusIconClass
             * @private
             *
             * @memberof RecordStatusController
             *
             * @param {Boolean} A boolean indicating whether or not the records being checked were valid
             * @param {Boolean} A boolean indicating whether or not a DNS lookup error occurred
             *
             * @return {Boolean} returns a string of font awesome classes and colors
             *
             */

            $scope._getStatusIconClass = function _getStatusIconClass(valid, nsError) {
                if (nsError) {
                    return "fa-times text-danger";
                }
                if (valid) {
                    return "fa-check text-success";
                }
                return "fa-exclamation-triangle text-warning";
            };

            /**
             * Generates a status description based on record validity
             *
             * @method _getStatusDescription
             * @private
             *
             * @param {Boolean} A boolean indicating whether or not the records being checked were valid
             * @param {Boolean} A boolean indicating whether or not a DNS lookup error occurred
             *
             * @return {Boolean} returns a string description of the status
             *
             */

            $scope._getStatusDescription = function _getStatusDescription(valid, nsError) {
                if (nsError) {
                    return LOCALE.maketext("One or more [asis,DNS] errors occurred while validating this domain.");
                }
                if (valid) {
                    return LOCALE.maketext("No problems exist on this domain.");
                }
                return LOCALE.maketext("One or more problems exist on this domain.");
            };

            /**
             * Generates a status label based on record validity
             *
             * @method _getStatusLabel
             * @private
             *
             * @param {Boolean} A boolean indicating whether or not the records being checked were valid
             * @param {Boolean} A boolean indicating whether or not a DNS lookup error occurred
             *
             * @return {Boolean} returns a string label of the status
             *
             */

            $scope._getStatusLabel = function _getStatusLabel(valid, nsError) {
                if ( nsError ) {
                    return LOCALE.maketext("[asis,DNS] Errors Occurred");
                }
                if (valid) {
                    return LOCALE.maketext("Valid");
                }
                return LOCALE.maketext("Problems Exist");
            };

            /**
             * Update the status variables this record from the domain status
             * Called by the watcher.
             *
             * @method _getStatusLabel
             * @private
             *
             */

            $scope._updateStatus = function _updateStatus() {

                if (!$scope.domain || !$scope.domain.recordsLoaded) {
                    $scope.recordLoading = true;
                } else {
                    var someRecordsFail = $scope.records.some(function(record) {
                        return !$scope.domain.isRecordValid(record);
                    });

                    var hadNSError = $scope.records.some(function(record) {
                        return $scope.domain.recordHadNSError(record);
                    });

                    var recordsValid = !someRecordsFail;

                    angular.extend($scope, {
                        statusIconClass: $scope._getStatusIconClass(recordsValid, hadNSError),
                        statusLabel: $scope._getStatusLabel(recordsValid, hadNSError),
                        statusDescription: $scope._getStatusDescription(recordsValid, hadNSError),
                        recordLoading: false
                    });
                }
            };

            $scope.getLoadingMessage = function getLoadingMessage() {
                if (!$scope.domain) {
                    return "";
                }
                if ($scope.domain.reloadingIn) {
                    return LOCALE.maketext("Rechecking the server records in [quant,_1,second,seconds] …", $scope.domain.reloadingIn);
                } else {
                    return LOCALE.maketext("Loading …");
                }
            };

            var unwatch = $scope.$watch(function() {
                if (!$scope.domain) {
                    return false;
                }
                return $scope.domain.recordsLoaded;
            }, $scope._updateStatus);

            if ($scope.domain) {
                $scope._updateStatus();
            }

            $scope.$on("$destroy", function() {
                unwatch();
            });

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        var DIRECTIVE_LINK = function(scope, element, attrs) {
            scope.recordLoading = true;
        };
        module.directive("recordStatus", function itemListerItem() {

            return {
                templateUrl: TEMPLATE_PATH,
                scope: {
                    parentID: "@id",
                    records: "=",
                    domain: "="
                },
                restrict: "EA",
                replace: false,
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
