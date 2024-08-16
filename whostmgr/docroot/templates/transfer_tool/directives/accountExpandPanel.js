/*
# templates/transfer_tool/controllers/AccountTableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/* jshint -W003 */
/* jshint -W098*/

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/workerNodes",
    ],
    function(angular, _, LOCALE, WorkerNodesService) {

        "use strict";

        var MODULE_NAMESPACE = "whm.transfers.directives.accountExpandPanel";
        var MODULE_INJECTABLES = [WorkerNodesService.namespace];

        var DIRECTIVE_NAME = "accountExpandPanel";

        /* embedded in getacctlist.tmpl so relative pathing is not necessary */
        var DIRECTIVE_TEMPLATE = "directives/accountExpandPanel.ptt";

        var CONTROLLER_INJECTABLES = ["$scope", WorkerNodesService.serviceName ];
        var CONTROLLER = function AccountExpandPanelController($scope, $workerNodesService) {

            function _resetSkipOption(skipOption) {
                $scope.account[skipOption.modelKey] = skipOption.default;
                $scope.skipOptionChanged(skipOption);
            }

            function _resetWorkerType(workerDefaultValueObj) {
                var modelKey = workerDefaultValueObj.modelKey;
                var defaultValue = workerDefaultValueObj.value;
                var workerType = workerDefaultValueObj.workerType;

                $scope.account[modelKey] = defaultValue;
                $scope.workerNodeOption[workerType] = $scope.findWorkerOptionByValue(workerType, defaultValue);
                $scope.workerNodeOptionChanged(workerType);
            }

            /**
             * Function Called when reset button is clicked from the view
             *
             */
            $scope.resetToDefaultClicked = function resetToDefaultClicked() {
                if ($scope.account.proxyOption) {
                    $scope.account.proxyOption.value = $scope.account.proxyOption.default;
                }
                $scope.skipOptions.forEach(_resetSkipOption);
                $workerNodesService.getAccountWorkerDefaultValues($scope.account).forEach(_resetWorkerType);
            };

            /**
             * Function called when 'apply to all' button is clicked from the view
             *
             */
            $scope.applyToAllClicked = function allToAllClicked() {
                $scope.onApplyToAll({ updatedAccount: $scope.account, skipOptions: $scope.skipOptions, workerOptions: $scope.workerNodeOption, proxyOption: $scope.account.proxyOption });
            };

            /**
             * Function called on change of a specific option from the view
             *
             * @param {object} skipOption
             */
            $scope.skipOptionChanged = function skipOptionChanged(skipOption) {
                $scope.onChange({ updatedAccount: $scope.account, modelKey: skipOption.modelKey, value: $scope.account[skipOption.modelKey] });
            };

            /**
             * Function called on change of proxying option froom view
             * @param  {object} proxyOption
             */
            $scope.proxyOptionChanged = function proxyOptionChanged(proxyOption) {
                $scope.onChange({ updatedAccount: $scope.account, modelKey: proxyOption.modelKey, value: !proxyOption.value });
            };

            /**
             * Check if all options are set to default
             *
             * @returns {boolean} If all options match the default, this is true, else false
             */
            $scope.isSetToDefault = function isSetToDefault() {
                return !$scope._skipOptionsAltered() && !$scope._workerOptionsAltered() && !$scope._proxyOptionAltered();
            };

            /**
             * Determine the number of accounts selected based on whether this account is selected or not
             *
             * @returns {number} Number of accounts selected
             */
            $scope.getOtherSelectedAccountsCount = function getOtherSelectedAccountsCount() {
                var count = $scope.selectedAccountsCount;
                if ($scope.account.selected && count > 0) {
                    count--;
                }
                return count;
            };

            /**
             * Dispatches a close call to allow the closing of the expansion panel
             *
             */
            $scope.applyAndClose = function applyAndClose() {
                $scope.onClose({ updatedAccount: $scope.account });
            };

            /**
             * Check to see if any skip options are altered
             *
             * @returns {boolean} returns true if any are altered
             */
            $scope._skipOptionsAltered = function _skipOptionsAltered() {
                return $scope.skipOptions.some(function(skipOption) {
                    if ($scope.account[skipOption.modelKey] !== skipOption.default) {
                        return true;
                    }
                    return false;
                });
            };

            /**
             * Check to see if proxying option has been changed
             * @return {boolean}
             */
            $scope._proxyOptionAltered = function _proxyOptionAltered() {
                if ($scope.account.proxyOption) {
                    return $scope.account.proxyOption.value !== $scope.account.proxyOption.default;
                }
                return false;
            };

            /**
             * Check to see if any worker options are altered
             *
             * @returns {boolean} returns true if any are altered
             */
            $scope._workerOptionsAltered = function _workerOptionsAltered() {
                return $workerNodesService.checkWorkerOptionsAltered($scope.account);
            };

            /**
             * Get the label for a worker option menu
             *
             * @param {string} workerType string identifier of the node type (Mail)
             * @returns {string} localized label
             */
            $scope.getWorkerConfigLabel = function getWorkerConfigLabel(workerType) {
                switch (workerType.toLowerCase()) {
                    case "mail":
                        return LOCALE.maketext("Mail");
                }
            };

            /**
             * Called when a worker node option changes
             *
             * @param {string} workerType the worker type that changed
             */
            $scope.workerNodeOptionChanged = function workerNodeOptionChanged(workerType) {
                var worker = $workerNodesService.getDefaultWorkerOptions()[workerType];
                $scope.onChange({ updatedAccount: $scope.account, modelKey: worker.modelKey, value: $scope.workerNodeOption[workerType].value });
            };

            /**
             * Find a specific worker option (object) by the .value property
             *
             * @param {string} workerType the worker type to search
             * @param {string} value the specific value to look for
             * @returns {object|null} returns the object if found
             */
            $scope.findWorkerOptionByValue = function findWorkerOptionByValue(workerType, value) {
                return _.find($scope.workerNodeOptions[workerType], function(workerOption) {
                    if (workerOption.value === value) {
                        return true;
                    }
                    return false;
                });
            };

            /**
             * Set the current value of a worker type (done on intiation)
             *
             * @param {string} workerType worker type to set
             */
            $scope.setCurrentWorkerTypeValue = function setCurrentWorkerTypeValue(workerType) {
                var modelKey = $workerNodesService.getDefaultWorkerOptions()[workerType].modelKey;
                $scope.workerNodeOption[workerType] = $scope.findWorkerOptionByValue(workerType, $scope.account[modelKey]);
            };

            // Build Worker Option Sets
            $scope.workerNodeOptions = $workerNodesService.getAccountWorkerNodeOptions($scope.account);
            $scope.workerNodeOption = {};

            $workerNodesService.getWorkerOptionTypes().forEach(function(workerType) {
                $scope.setCurrentWorkerTypeValue(workerType);
                var modelKey = $workerNodesService.getDefaultWorkerOptions()[workerType].modelKey;

                // Watch changes on the account
                $scope.$watch(function() {
                    return $scope.account[modelKey];
                }, function() {
                    $scope.setCurrentWorkerTypeValue(workerType);
                });
            });

            // We should only show worker choices if there is greater than one thing to choose
            // because only one thing means that there is only .local
            $scope.showWorkerNodeOptions = $workerNodesService.getWorkerOptionTypes().some(function(typeKey) {
                if ($scope.workerNodeOptions[typeKey].length > 1) {
                    return true;
                }
                return false;
            });
        };
        var LINK = function AccountExpandPanelLink($scope, element, attrs) {
            if ( _.isUndefined($scope.parentID) ) {
                throw new Error("“id” must be set for " + DIRECTIVE_NAME);
            }

            if ( _.isUndefined($scope.account) ) {
                throw new Error("“account” must be set for " + DIRECTIVE_NAME);
            }

            if ( _.isUndefined($scope.selectedAccountsCount) ) {
                throw new Error("“selectedAccountsCount” must be set for " + DIRECTIVE_NAME);
            }

            if (!$scope.skipOptions) {
                $scope.skipOptions = [];
            }

            $scope.selectedAccountsCount = parseInt($scope.selectedAccountsCount, 10);

            $scope.skipOptions.forEach(function validateSkipOption(skipOption) {
                var requiredParameters = ["label", "id", "modelKey", "default"];
                requiredParameters.forEach(function(param) {
                    if ( _.isUndefined(skipOption[param]) ) {
                        throw new Error("[" + DIRECTIVE_NAME + "] all skip-options items must have the following parameters:\n" + requiredParameters.join(", ") + "\nInvalid item:\n" + JSON.stringify(skipOption));
                    }
                });

                skipOption.id = $scope.parentID + "_" + skipOption.id;
            });
        };
        var DIRECTIVE_FACTORY = function DirectiveFactory() {

            return {
                restrict: "E",
                transclude: true,
                scope: {
                    parentID: "@id",
                    skipOptions: "=",
                    proxyOption: "=",
                    account: "=",
                    selectedAccountsCount: "@",
                    onApplyToAll: "&onApplyToAll",
                    onChange: "&onChange",
                    onClose: "&onClose",
                },
                link: LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER),
                templateUrl: DIRECTIVE_TEMPLATE,

            };
        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_INJECTABLES);
        module.directive(DIRECTIVE_NAME, DIRECTIVE_FACTORY);

        return {
            namespace: MODULE_NAMESPACE,
            class: CONTROLLER,
            factory: LINK,
            template: DIRECTIVE_TEMPLATE
        };

    }
);
