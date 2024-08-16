/*
 * backup_user_selection/services/backupUserSelectionService.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */
define(
    'app/services/backupUserSelectionService',[
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
        "cjt/services/APIService"
    ],
    function(
        angular,
        LOCALE,
        PARSE,
        APIREQUEST) {
        "use strict";

        var app = angular.module("whm.backupUserSelection.backupUserSelectionService.service", []);
        app.value("PAGE", PAGE);

        app.factory("backupUserSelectionService", [
            "$q",
            "APIService",
            "PAGE",
            function($q, APIService, PAGE) {

                /**
                 * @typedef AccountDataType
                 * @property {String} user - account user name
                 * @property {String} domain - account domain name
                 * @property {Boolean} backup - if backups are enabled for account
                 * @property {Number} uid - unique account id
                 * @property {Boolean} legacy_backup- if legacy backups are enabled for account
                 */

                /**
                 * Parse raw response into usable data for front end
                 *
                 * @private
                 * @method parseAccountData
                 * @param  {Array.<AccountDataType>} accountData - raw response from API
                 * @return {Array.<AccountDataType>} parsed data for use in front end
                 */
                function parseAccountData(accountData) {
                    var data = accountData;
                    var accounts = accountData.data;
                    var cleanAccounts = [];
                    var cleanAccount;

                    if (accountData.data) {
                        accounts.forEach(function(account) {
                            cleanAccount = {};
                            cleanAccount.user = account.user;
                            cleanAccount.domain = account.domain;
                            cleanAccount.uid = account.uid;
                            cleanAccount.legacy_backup = PARSE.parsePerlBoolean(account.legacy_backup);
                            cleanAccount.backup = PARSE.parsePerlBoolean(account.backup);
                            cleanAccounts.push(cleanAccount);
                        });
                    }
                    data.data = cleanAccounts;
                    return data;
                }

                var BackupUserSelectionService = function() {};


                BackupUserSelectionService.prototype = new APIService();

                angular.extend(BackupUserSelectionService.prototype, {

                    /**
                     * Fetch account data
                     *
                     * @async
                     * @method getUserAccounts
                     * @return {Promise<Array.<AccountDataType>>} - array of account objects
                     * @throws {Promise<String>} error message on failure
                     */
                    getUserAccounts: function() {
                        var apiRequest = new APIREQUEST.Class();
                        apiRequest.initialize("", "listaccts");
                        apiRequest.addArgument("want", "user,domain,uid,backup,legacy_backup");

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: parseAccountData
                        });

                        return deferred.promise;
                    },

                    /**
                     * Enable or disable backups on account
                     *
                     * @async
                     * @method toggleAccount
                     * @param  {String} username - account username
                     * @param  {Boolean} isLegacy - if toggling legacy account
                     * @return {Promise<String>} - string indicating successful update
                     * @throws {Promise<String>} - error message on failure
                     */
                    toggleAccount: function(username, isLegacy) {
                        var apiRequest = new APIREQUEST.Class();
                        apiRequest.initialize("", "toggle_user_backup_state");
                        apiRequest.addArgument("user", username);
                        apiRequest.addArgument("legacy", isLegacy ? 1 : 0);

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(toggledData) {
                                return PARSE.parsePerlBoolean(toggledData.data.toggle_status);
                            }
                        });

                        return deferred.promise;
                    }
                });

                return new BackupUserSelectionService();
            }
        ]);
    });

/*
# templates/backup_user_selection/services/NVData.js
                                                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/NVData',[
        "angular",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, _, API, APIREQUEST, APIDRIVER) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("whm.backupUserSelection");

        var nvdata = app.factory("NVData", ["$q", function($q) {
            var obj = {};

            obj.get = function(key) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "nvget");

                apiCall.addArgument("key", key);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var obj = response.data.nvdatum;
                            var returnObj = {};

                            returnObj.key = obj.key;
                            if (Array.isArray(obj.value)) {
                                if (obj.value.length === 1) {
                                    returnObj.value = obj.value[0];
                                } else {
                                    returnObj.value = obj.value;
                                }
                            } else {
                                returnObj.value = obj.value;
                            }

                            deferred.resolve(returnObj);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;

            };

            obj.set = function(key, value) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "nvset");

                apiCall.addArgument("key1", key);
                apiCall.addArgument("value1", value);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var obj;
                            var returnObj = {};

                            if (typeof response.data.nvdatum !== "undefined") {
                                obj = response.data.nvdatum;
                            } else {
                                obj = response.data;
                            }

                            if (Array.isArray(obj) && obj.length > 0) {
                                returnObj.key = obj[0].key;
                                returnObj.value = obj[0].value;
                            }

                            returnObj.status = response.status;

                            deferred.resolve(returnObj);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;

            };

            return obj;
        }]);

        return nvdata;
    }
);

/*
# backup_user_selection/views/backupUserSelectionView.js      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/backupUserSelectionView',[
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

/*
# backup_user_selection/index.js                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "app/services/backupUserSelectionService",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/directives/callout"
    ],
    function(angular, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.backupUserSelection", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "angular-growl",
                "cjt2.whm",
                "whm.backupUserSelection.backupUserSelectionService.service"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/views/backupUserSelectionView",
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.backupUserSelection");
                    app.value("PAGE", PAGE);


                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/backupUserSelectionView", {
                                controller: "backupUserSelectionView",
                                templateUrl: "views/backupUserSelectionView.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/backupUserSelectionView"
                            });
                        }
                    ]);

                    var appContent = angular.element("#pageContainer");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        BOOTSTRAP(appContent[0], "whm.backupUserSelection");
                    }

                });

            return app;
        };
    }
);

