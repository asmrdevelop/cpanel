/*
 * backup_user_selection/services/backupUserSelectionService.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */
define(
    [
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
