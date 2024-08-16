/*
# file_and_directory_restore/services/backup_API.js        Copyright 2017 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/backup_API',[
        "angular",
        "cjt/io/uapi-request",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"

    ],
    function(angular, APIREQUEST, API, WHMREQUEST, APIDRIVER) {
        var app;
        try {
            app = angular.module("whm.fileAndDirectoryRestore"); // For runtime
        } catch (e) {
            app = angular.module("whm.fileAndDirectoryRestore", []); // Fall-back for unit testing
        }

        app.factory("backupAPIService", [
            "APIService",
            function(
                APIService
            ) {

                // Set up the service's constructor and parent
                var BackupAPIService = function() {};
                BackupAPIService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(BackupAPIService.prototype, {
                    /**
                     * Get a list of all directories and files of a given path
                     * @public
                     * @method listDirectory
                     * @param {string} path The full path of the directory
                     * @param {string} accountName Name of user to get backups for
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    listDirectory: function(path, accountName) {

                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "directory_listing");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("path", path);

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                return response.data;
                            },
                            transformAPIFailure: function(response) {
                                return response.error;
                            }
                        });

                        return deferred.promise;
                    },
                    /**
                     * Get all users in WHM account
                     * @public
                     * @method listUsers
                     * @return {Promise} Promise that will fulfill the request.
                     **/
                    listUsers: function() {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("Accounts", "listaccts");

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                return response.data;
                            },
                            transformAPIFailure: function(response) {
                                return response.error;
                            }
                        });
                        return deferred.promise;
                    },
                    /**
                     * Get all backups of a particular file
                     * @public
                     * @method listFileBackups
                     * @param {string} fullPath The full path of the file
                     * @param {string} accountName The cpanl user name
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    listFileBackups: function(fullPath, accountName) {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "query_file_info");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("fullpath", fullPath);

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                return response.data;
                            },
                            transformAPIFailure: function(response) {
                                return response.error;
                            }
                        });

                        return deferred.promise;
                    },
                    /**
                     * Restore a single file
                     * @public
                     * @method restore
                     * @param {string} fullPath The full path of the file
                     * @param {string} backupID The full path of the backup
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    restore: function(fullPath, backupID, accountName) {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "restore_file");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("backupID", backupID);
                        apiCall.addArgument("fullpath", fullPath);
                        apiCall.addArgument("overwrite", 1);

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                return response.data;
                            },
                            transformAPIFailure: function(response) {
                                return response.error;
                            }
                        });

                        return deferred.promise;
                    },
                });

                return new BackupAPIService();
            }
        ]);
    }
);
/*
# file_and_directory_restore/views/backup_restore.js                   Copyright 2017 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/backup_restore',[
        "angular",
        "cjt/util/locale",
        "app/services/backup_API",
        "uiBootstrap"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("whm.fileAndDirectoryRestore");

        // Setup the controller
        var controller = app.controller(
            "listController", [
                "$scope",
                "growl",
                "backupAPIService",
                "$uibModal",
                function(
                    $scope,
                    growl,
                    backupAPIService,
                    $uibModal
                ) {
                    /**
                     * Called when path changes
                     *
                     * @scope
                     * @method buildBreadcrumb
                     */
                    $scope.buildBreadcrumb = function() {
                        $scope.directoryBreadcrumb = [];
                        // If at root directory, no path is needed and the full string of currentPath is the entirety of directoryBreadcrumb
                        if ($scope.currentPath === "/") {
                            $scope.directoryBreadcrumb = [{
                                folder: $scope.currentPath,
                                path: $scope.currentPath
                            }];
                        } else {
                            // If in a sub-directory, build each directoryBreadcrumb element splitted by "/" and build each path
                            var directories = $scope.currentPath.split("/");
                            for (var i = 0, length = directories.length; i < length; i++) {
                                $scope.directoryBreadcrumb.push({
                                    folder: directories[i],
                                    path: $scope.currentPath.split(directories[i])[0] + directories[i]
                                });
                            }
                        }
                    };

                    /**
                     * Change to a different directory and get the list of files in that directory
                     *
                     * @scope
                     * @method changeDirectory
                     * @param  {String} path file system path user is directing to
                     */
                    $scope.changeDirectory = function(path) {
                        $scope.loadingData = true;
                        $scope.fileBackupList = [];
                        // Call API to fetch the new directory info

                        if (path === "..") {
                            path = $scope.directoryBreadcrumb[$scope.directoryBreadcrumb.length - 3].path;
                        }

                        // add necessary trailing slash to path string for proper API format
                        if (path.charAt(path.length - 1) !== "/") {
                            path = path + "/";
                        }

                        backupAPIService.listDirectory(path, $scope.accountName)
                            .then(function(directoryPath) {
                                $scope.currentPath = path;
                                $scope.buildBreadcrumb();
                                $scope.addPaths(directoryPath);
                                $scope.loadingData = false;
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    /**
                     * Select an item, get the backup list of that item or change to that directory
                     *
                     * @scope
                     * @method selectItem
                     * @param  {Object} item file or directory user selects
                     */
                    $scope.selectItem = function(item) {
                        if (item.type.indexOf("dir") !== -1) {
                            $scope.changeDirectory(item.fullPath);
                        } else {
                            $scope.selectedItemName = item.name;
                            $scope.selectedItemExists = item.exists;
                            $scope.loadingData = true;
                            backupAPIService.listFileBackups(item.fullPath, $scope.accountName)
                                .then(function(itemData) {
                                    $scope.fileBackupList = itemData;
                                    $scope.loadingData = false;
                                }, function(error) {
                                    growl.error(error);
                                });
                        }
                    };

                    /**
                     * Adds the full path (path names for children of current directory)
                     * to the data and the path (path to current directory location)to the parent directory
                     * as properties on the data object
                     *
                     * @scope
                     * @method addPaths
                     * @param {Array} directories Array of data objects that need path properties added.
                     **/
                    $scope.addPaths = function(directories) {
                        $scope.currentDirectoryContent = [];
                        for (var i = 0, length = directories.length; i < length; i++) {
                            directories[i]["path"] = $scope.currentPath;
                            directories[i]["fullPath"] = $scope.currentPath + directories[i].name;
                            $scope.currentDirectoryContent.push(directories[i]);
                        }
                    };

                    /**
                     * Process requested backup version to restore a single file
                     *
                     * @scope
                     * @method restore
                     * @param {Object} backup selected to be processed
                     *   @param {string} fullpath The full path to the target file location
                     *   @param {string} backupID The backup's path on the disk
                     **/
                    $scope.restore = function(backup) {
                        $scope.selectedFilePath = backup.fullpath;
                        $scope.selectedBackupID = backup.backupID;
                        var $uibModalInstance = $uibModal.open({
                            templateUrl: "restoreModalContent.tmpl",
                            controller: "restoreModalController",
                            resolve: {
                                fileExists: $scope.selectedItemExists
                            }
                        });

                        $uibModalInstance.result.then(function(proceedRestoration) {
                            if (proceedRestoration) {
                                // Run restoration
                                backupAPIService.restore($scope.selectedFilePath, $scope.selectedBackupID, $scope.accountName)
                                    .then(function(response) {
                                        if (response.success) {
                                            growl.success(LOCALE.maketext("File restored successfully."));
                                        }
                                    }, function(error) {
                                        growl.error(LOCALE.maketext("File restoration failure: [_1]", error));
                                    });
                            }
                        });
                    };
                    /**
                     * Get list of all user accounts listed in WHM
                     *
                     * @scope
                     * @method getAccounts
                     **/
                    $scope.getAccounts = function() {
                        backupAPIService.listUsers()
                            .then(function(accounts) {
                                $scope.inCpanel = false;
                                $scope.initialDataLoaded = true;
                                $scope.accounts = accounts;
                                $scope.currentDirectoryContent = [];
                                $scope.fileBackupList = [];
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    /**
                     * Get file and directory listing of specific account
                     *
                     * @scope
                     * @method getAccount
                     * @param {string} accountName name of account user is retrieving backups for
                     **/

                    $scope.getAccount = function(accountName) {
                            $scope.loadingData = true;
                            backupAPIService.listDirectory("/", accountName)
                                .then(function(directoryPath) {
                                    $scope.inCpanel = true;
                                    $scope.accountName = accountName;
                                    $scope.currentPath = "/";
                                    $scope.loadingData = false;
                                    $scope.buildBreadcrumb();
                                    $scope.addPaths(directoryPath);
                                }, function(error) {
                                    growl.error(error);
                                });
                        },

                        /**
                         * Initializes data
                         * @scope
                         * @method init
                         **/

                        $scope.init = function() {
                            $scope.initialDataLoaded = false;
                            $scope.getAccounts();
                        };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
/*
# file_and_directory_restore/views/restore_cnfirmation.js  Copyright 2017 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define('app/views/restore_confirmation',[
    "angular",
    "cjt/util/locale",
    "uiBootstrap"
], function(angular, LOCALE) {

    var app = angular.module("whm.fileAndDirectoryRestore");

    app.controller("restoreModalController", [
        "$scope",
        "$uibModalInstance",
        "fileExists",
        function(
            $scope,
            $uibModalInstance,
            fileExists
        ) {
            $scope.fileExists = fileExists;
            $scope.closeModal = function() {
                $uibModalInstance.close();
            };

            $scope.runIt = function() {
                $uibModalInstance.close(true);
            };
        }
    ]);
});
/*
# file_and_backup_restoration/filters/file_size_filter.js    Copyright 2017 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/file_size_filter',[
        "angular",
        "cjt/util/locale"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app;
        try {
            app = angular.module("whm.fileAndDirectoryRestore"); // For runtime
        } catch (e) {
            app = angular.module("whm.fileAndDirectoryRestore", []); // Fall-back for unit testing
        }

        app.filter("convertedSize", function() {
            return function(size) {
                return LOCALE.format_bytes(size);
            };
        });
    });
/*
# whostmgr/docroot/templates/file_and_directory_restore/index.js
#                                                 Copyright 2017 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require: false, define: false */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, CJT) {
        return function() {
            angular.module("whm.fileAndDirectoryRestore", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/views/backup_restore",
                    "app/views/restore_confirmation",
                    "app/filters/file_size_filter"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.fileAndDirectoryRestore");

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {
                            $routeProvider.when("/backup_restore", {
                                controller: "listController",
                                templateUrl: "file_and_directory_restore/views/backup_restore.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/backup_restore"
                            });
                        }
                    ]);

                    BOOTSTRAP(document, "whm.fileAndDirectoryRestore");

                });

            return app;
        };
    }
);
