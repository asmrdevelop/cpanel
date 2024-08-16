/*
# backup_user_selection/views/backupUserSelectionView.js      Copyright 2022 cPanel, L.L.C.
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
        "cjt/util/table",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/alert",
        "cjt/directives/loadingPanel",
        "cjt/services/alertService",
        "app/services/NVData",
        "app/services/backupUserSelectionService"
    ],
    function(angular, _, LOCALE, Table, PARSE) {
        "use strict";

        var app = angular.module("whm.backupUserSelection");

        var controller = app.controller(
            "backupUserSelectionView", ["$q", "$scope", "backupUserSelectionService", "NVData", "PAGE", "alertService",
                function($q, $scope, backupUserSelectionService, NVData, PAGE, alertService) {
                    var table = new Table();

                    function searchByUsernameOrDomain(account, searchExpression) {
                        searchExpression = searchExpression.toLowerCase();

                        return account.user.toLowerCase().indexOf(searchExpression) !== -1 ||
                            account.domain.toLowerCase().indexOf(searchExpression) !== -1;
                    }

                    table.setSearchFunction(searchByUsernameOrDomain);

                    /**
                     * Fetches account data
                     *
                     * @scope
                     * @method getUserAccounts
                     */
                    $scope.getUserAccounts = function() {
                        $scope.action.loading = true;

                        backupUserSelectionService.getUserAccounts()
                            .then(function(response) {
                                $scope.accountData = response.data;
                                $scope.getInitialPageSize($scope.accountData);
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    group: "backupUserSelection",
                                    closeable: true
                                });
                            })
                            .finally(function() {
                                $scope.action.loading = false;
                            });
                    };

                    /**
                     * Enable or disable backup on account
                     *
                     * @scope
                     * @method toggleAccount
                     * @param  {String} username - account username
                     * @param  {Boolean} isLegacy - if it is the legacy backup type being toggled
                     */
                    $scope.toggleAccount = function(account, isLegacy) {
                        $scope.action.toggling = true;
                        backupUserSelectionService.toggleAccount(account.user, isLegacy)
                            .then(function(response) {
                                if (isLegacy) {
                                    account.legacy_backup = response;
                                } else {
                                    account.backup = response;
                                }
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    group: "backupUserSelection",
                                    closeable: true
                                });
                            })
                            .finally(function() {
                                $scope.action.toggling = false;
                            });
                    };

                    /**
                     * Inserts data into table directive on initial call
                     *
                     * @scope
                     * @method setPagination
                     * @param {Array.<AccountDataType>} [accountData] - array of account data
                     * @param {Number}                  [pageSize] - initial pagination size
                     */
                    $scope.setPagination = function(accountData, pageSize) {

                        // Add data to table on initial page load.
                        table.load(accountData);
                        table.setSort("user", "asc");

                        // Set page size on initial load
                        $scope.meta = table.getMetadata();
                        $scope.meta.pageSize = pageSize;

                        $scope.setTable();
                    };

                    /**
                     * Updates table and sets scoped variables for table
                     *
                     * @scope
                     * @method setTable
                     */
                    $scope.setTable = function() {
                        table.update();

                        $scope.meta = table.getMetadata();
                        $scope.filteredAccountList = table.getList();
                        $scope.paginationMessage = table.paginationMessage();
                        $scope.action.toggling = false;
                        $scope.showPager = true;
                    };

                    /**
                     * Fetch saved page size data
                     *
                     * @scope
                     * @method getInitialPageSize
                     * @param  {Array.<AccountDataType>} accountData - array of account objects
                     */
                    $scope.getInitialPageSize = function(accountData) {
                        NVData.get("accounts_page_size")
                            .then(function(pageSize) {
                                pageSize = parseInt(pageSize.value, 10) || 10;
                                $scope.setPagination(accountData, pageSize);
                            });
                    };

                    /**
                     * Set and save page size data
                     *
                     * @scope
                     * @method setPageSize
                     */
                    $scope.setPageSize = function() {
                        $scope.setTable();
                        NVData.set("accounts_page_size", $scope.meta.pageSize);
                    };

                    /**
                     * Fetch saved page size data
                     *
                     * @scope
                     * @method getInitialPageSize
                     * @param  {Array.<AccountDataType>} accountData - array of account objects
                     */
                    $scope.getInitialPageSize = function(accountData) {
                        NVData.get("accounts_page_size")
                            .then(function(pageSize) {
                                pageSize = parseInt(pageSize.value, 10) || 10;
                                $scope.setPagination(accountData, pageSize);
                            });
                    };

                    /**
                     * Set and save page size data
                     *
                     * @scope
                     * @method setPageSize
                     */
                    $scope.setPageSize = function() {
                        $scope.setTable();
                        NVData.set("accounts_page_size", $scope.meta.pageSize);
                    };

                    /**
                     * Enables backups for every account
                     *
                     * @scope
                     * @method enableAllAccounts
                     * @param {Boolean} isLegacy - if user is enabling legacy backup types
                     * @return {Array.<Promise<String>>} an array of strings indicating success for each account
                     */
                    $scope.enableAllAccounts = function(isLegacy) {
                        var promises = [];
                        $scope.action.toggling = true;
                        angular.forEach($scope.accountData, function(account) {
                            if ((!account.backup && !isLegacy) || (!account.legacy_backup && isLegacy)) {
                                promises.push(
                                    backupUserSelectionService.toggleAccount(account.user, isLegacy)
                                        .then(function(response) {
                                            if (isLegacy) {
                                                account.legacy_backup = response;
                                            } else {
                                                account.backup = response;
                                            }
                                        }, function(error) {
                                            alertService.add({
                                                type: "danger",
                                                message: error,
                                                group: "backupUserSelection",
                                                closeable: true
                                            });
                                        }));
                            }

                        });

                        return $q.all(promises).finally(function() {
                            $scope.action.toggling = false;
                        });
                    };

                    /**
                     * Disables backups for every account
                     *
                     * @scope
                     * @method disableAllAccounts
                     * @param {Boolean} isLegacy - if user is disabling legacy backup types
                     * @return {Array.<Promise<String>>} an array of strings indicating success for each account
                     */
                    $scope.disableAllAccounts = function(isLegacy) {
                        var promises = [];
                        $scope.action.toggling = true;
                        angular.forEach($scope.accountData, function(account) {
                            if ((account.backup && !isLegacy) || (account.legacy_backup && isLegacy)) {
                                promises.push(
                                    backupUserSelectionService.toggleAccount(account.user, isLegacy)
                                        .then(function(response) {
                                            if (isLegacy) {
                                                account.legacy_backup = response;
                                            } else {
                                                account.backup = response;
                                            }
                                        }, function(error) {
                                            alertService.add({
                                                type: "danger",
                                                message: error,
                                                group: "backupUserSelection",
                                                closeable: true
                                            });
                                        }));
                            }

                        });

                        return $q.all(promises).finally(function() {
                            $scope.action.toggling = false;
                        });
                    };

                    /**
                     * Initializes controller
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.action = {
                            loading: false,
                            toggling: false,
                            settingPage: false
                        };
                        $scope.meta = {};
                        $scope.getUserAccounts();
                        $scope.legacyBackupEnabled = PARSE.parsePerlBoolean(PAGE.legacyBackupEnabled);
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
