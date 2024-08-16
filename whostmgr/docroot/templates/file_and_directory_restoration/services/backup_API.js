/*
# file_and_directory_restoration/services/backup_API.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/io/uapi-request",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"

    ],
    function(angular, LOCALE, APIREQUEST, API, WHMREQUEST, APIDRIVER) {
        "use strict";
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
                var validBackupTypes = {
                    "compressed": LOCALE.maketext("Compressed"),
                    "uncompressed": LOCALE.maketext("Uncompressed"),
                    "incremental": LOCALE.maketext("Incremental")
                };

                /**
                 * Parse raw data for consumption by front end
                 *
                 * @private
                 * @method parseBackupData
                 * @param  {object} backupData - raw data object
                 * @return {object} parsed data for front end
                 */
                function parseBackupData(backupData) {
                    var backups = backupData.data;
                    var parsedBackups = [];

                    backups.forEach(function(backup) {
                        backup.mtime = LOCALE.local_datetime(parseInt(backup.mtime, 10), "datetime_format_short");
                        if (validBackupTypes.hasOwnProperty(backup.backupType)) {
                            backup.backupType = validBackupTypes[backup.backupType];
                        } else {
                            throw "DEVELOPER ERROR: Invalid backup type";
                        }
                        parsedBackups.push(backup);
                    });

                    return parsedBackups;
                }

                function parseHomeDirectory(accountData) {
                    accountData = accountData.data[0];
                    var homeDirectory = "/" + accountData.partition + "/" + accountData.user + "/";
                    return homeDirectory;
                }

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
                     * @param {string} pageStart The item index of start position
                     * @param {string} pageSize Number of items in each page requested
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    listDirectoryContents: function(path, accountName, pageStart, pageSize) {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "directory_listing");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("path", path);

                        // Pagination (UAPI doesn't support standard apiCall.addPaging(), so adding individual args)
                        apiCall.addArgument("api.paginate", 1);
                        apiCall.addArgument("api.paginate_start", pageStart);
                        apiCall.addArgument("api.paginate_size", pageSize);

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                return response;
                            },
                            transformAPIFailure: function(response) {
                                return response.error;
                            }
                        });

                        return deferred.promise;
                    },

                    getUserHomeDirectory: function(userName) {
                        var apiRequest = new WHMREQUEST.Class();
                        apiRequest.initialize("", "accountsummary");
                        apiRequest.addArgument("user", userName);

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: parseHomeDirectory
                        });
                        return deferred.promise;
                    },

                    /**
                     * Get all users in WHM account with backups enabled
                     * @public
                     * @method listUsers
                     * @return {Promise} Promise that will fulfill the request.
                     **/
                    listUsers: function(accountName) {
                        var deferred;
                        var apiCall = new WHMREQUEST.Class();
                        if (accountName !== "root") {
                            apiCall.initialize("", "cpanel");
                            apiCall.addArgument("cpanel_jsonapi_user", accountName);
                            apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                            apiCall.addArgument("cpanel_jsonapi_func", "get_users");
                            apiCall.addArgument("cpanel_jsonapi_apiversion", "3");

                            deferred = this.deferred(apiCall, {
                                transformAPISuccess: function(response) {
                                    if (response.data !== null) {
                                        return response.data.map( function(x) {
                                            return { user: x };
                                        } );
                                    }
                                    return [];
                                },
                                transformAPIFailure: function(response) {
                                    return response.error;
                                }
                            });
                            return deferred.promise;
                        }
                        apiCall.initialize("", "get_users_and_domains_with_backup_metadata");

                        deferred = this.deferred(apiCall, {
                            transformAPISuccess: function(response) {
                                if (response.data !== null) {
                                    return Object.keys(response.data).map( function(x) {
                                        return { user: x, domain: response.data[x] };
                                    } );
                                }
                                return [];
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
                     * @method listBackups
                     * @param {string} fullPath The full path of the file
                     * @param {string} accountName The cpanel user name
                     * @return {Promise} Promise that will fulfill the request.
                     */
                    listBackups: function(path, accountName, exists) {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "query_file_info");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("path", path);
                        apiCall.addArgument("exists", exists);

                        var deferred = this.deferred(apiCall, {
                            transformAPISuccess: parseBackupData,

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
                    restoreBackup: function(path, backupID, accountName) {
                        var apiCall = new WHMREQUEST.Class();
                        apiCall.initialize("", "cpanel");
                        apiCall.addArgument("cpanel_jsonapi_user", accountName);
                        apiCall.addArgument("cpanel_jsonapi_module", "Restore");
                        apiCall.addArgument("cpanel_jsonapi_func", "restore_file");
                        apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                        apiCall.addArgument("backupID", backupID);
                        apiCall.addArgument("path", path);
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
