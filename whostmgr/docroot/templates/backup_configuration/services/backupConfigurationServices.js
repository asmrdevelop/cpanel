/*
 * backup_configuration/services/backupConfigurationServices.js
 *                                                  Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */
define(
    [
        "angular",
        "lodash",
        "cjt/util/parse",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
        "cjt/services/APIService",
    ],
    function(
        angular,
        _,
        PARSE,
        APIREQUEST) {
        "use strict";

        var NO_MODULE = "";

        var app = angular.module("whm.backupConfiguration.backupConfigurationServices.service", []);
        app.value("PAGE", PAGE);

        /**
         * @constant {Array} BOOLEAN_PROPERTIES
         * @description Perl boolean properties from backup configuration to be parsed into JavaScript boolean
         **/
        var BOOLEAN_PROPERTIES = [
            "backup_daily_enable",
            "backup_monthly_enable",
            "backup_weekly_enable",
            "backupaccts",
            "backupbwdata",
            "backupenable",
            "backupfiles",
            "backuplogs",
            "backupmount",
            "backupsuspendedaccts",
            "check_min_free_space",
            "force_prune_daily",
            "force_prune_monthly",
            "force_prune_weekly",
            "keeplocal",
            "linkdest",
            "localzonesonly",
            "postbackup",
            "psqlbackup",
        ];

        /**
         * @constant {Array} NUMBER_PROPERTIES
         * @description properties to be parsed into numbers
         */
        var NUMBER_PROPERTIES = [
            "backup_daily_retention",
            "backup_monthly_retention",
            "backup_weekly_day",
            "backup_weekly_retention",
            "errorthreshhold",
            "maximum_restore_timeout",
            "maximum_timeout",
            "min_free_space",
        ];

        /**
         * @constant {Array} NUM_STRING_PROPERTIES
         * @description properties where the value is a string of numbers that will be parsed into JavaScript object
         */
        var NUM_STRING_PROPERTIES = [
            "backup_monthly_dates",
            "backupdays",
        ];

        app.factory("backupConfigurationServices", [
            "$q",
            "APIService",
            "PAGE",
            function($q, APIService, PAGE ) {

                var configService = this;

                configService.settings = null;
                configService.destinations = [];

                /**
                 * @typedef BackupConfiguration
                 * @property {String | Boolean} [backup_daily_enable = 1] - whether to enable daily backups
                 * @property {String | Boolean} [postbackup = 0] - whether to run `postcpbackup` script after backup finishes
                 * @property {String | Boolean} [backupenable = 0] - whether to enable backups
                 * @property {String | Boolean} [backup_monthly_enable = 0] - whether to enable monthly backups
                 * @property {String}           [backuptype = compressed] - type of backup to create
                 * @property {Number}           [backup_daily_retention = 5] - number of daily backups to retain
                 * @property {String}           [backupdays = 0,2,4,6] - which days of the week to run daily backups
                 * @property {String}           [backup_monthly_dates = 1] - which days of the month to run backups
                 * @property {Number}           [backup_weekly_day = 1] - which day of the week to run weekly backups
                 * @property {String | Boolean} [backup_weekly_enable = 0] - whether to enable weekly backups
                 * @property {Number}           [backup_weekly_retention = 1] - the number of weekly backups to retain
                 * @property {Number}           [maximum_restore_timeout = 21600] - how long a restoration will attempt to run, in seconds
                 * @property {Number}           [maximum_timeout = 7200] - how long a backup will atempt to run, in seconds
                 * @property {String | Boolean} [backupfiles = 1] - whether to back up system files
                 * @property {String | Boolean} [backupaccts = 1] - whether to back up accounts
                 * @property {String | Boolean} [keeplocal = 1] - whether to delete backups from the local directory
                 * @property {String | Boolean} [localzonesonly = 0] - whether to use `/var/named/domain.tld` or dnsadmin (1 = file, 0 = dnsadmin)
                 * @property {String | Boolean} [backupbwdata = 1] - whether to backup bandwidth tracking data
                 * @property {String | Boolean} [backuplogs = 0] - whether to back up the error logs
                 * @property {String | Boolean} [backupsuspendedaccts = 0] - whether to back up suspended accounts
                 * @property {String}           [backupdir = /backup] - primary backup directory
                 * @property {String | Boolean} [backupmount = 0] - whether to mount a backup partition
                 * @property {String}           [mysqlbackup = accounts] - backup method to use for MySQL databases
                 * @property {Number}           [backup_monthly_retention = 1] - number of monthly backups to keep
                 * @property {String | Boolean} [check_min_free_space = 0] - check whether destination server has minimum space required
                 * @property {String | Number}  [min_free_space = 5] - minimum amount of free space to check for on destination server
                 * @property {String}           [min_free_space_unit = percent] - unit of measure of disk space
                 * @property {String | Boolean} [force_prune_daily = 0] - whether to strictly enforce daily retention
                 * @property {String | Boolean} [force_prune_weekly = 0] - whether to strictly enforce weekly retention
                 * @property {String | Boolean} [force_prune_monthly = 0] - whether to strictly enforce monthly retention
                 */

                /**
                 * @typedef TransportType
                 * @description common properties for all transport types
                 * @property {String}           name - backup transport's name
                 * @property {String}           type - backup transport type
                 * @property {String | Boolean} disabled = 0 - whether to disable backup transport (1 = disabled, 0 = enabled)
                 * @property {String}           upload_system_backup = off - whether to upload system backups
                 * @property {String | Boolean} only_used_for_logs = 0 - whether to use this destination for only logs (0 = used for all backups, 1 = only logs are backed up here)
                 */

                /**
                 * @typedef CustomTransportType
                 * @augments TransportType
                 * @property {String}          script - valid absolute path to transport solution script
                 * @property {String}          host - valid remote server hostname
                 * @property {String}          path - valid file path to backup directoy on remote server
                 * @property {String | Number} [timeout = 30] - session timeout
                 * @property {String}          username - remote server account's username
                 * @property {String}          åpassword - remote server account's password
                 */

                /**
                 * @typedef FTPTransportType
                 * @augments TransportType
                 * @property {String}           host - a remote server's hostname
                 * @property {Number}           [port = 21] - remote server's FTP port
                 * @property {String}           path - path to backups directory on remote server
                 * @property {String | Boolean} [passive = 1] - whether to use passive FTP
                 * @property {String | Number}  [timeout = 30] - session timeout
                 * @property {String}           username - remote server account's username
                 * @property {String}           password - remote server account's password
                 */

                /**
                 * @typedef GoogleTransportType
                 * @augments TransportType
                 * @property {String}          client_id - unique user is provided by Google API
                 * @property {String}          cliend_secret - unique secret provided by Google API
                 * @property {String}          folder - backups folder in Google Drive
                 * @property {String | Number} [timeout = 30] - session timeout
                 */

                /**
                 * @typedef LocalTransportType
                 * @augments TransportType
                 * @property {String | Boolean} [mount = 0] - whether the path is mounted
                 * @property {String}           path - valid path to backups directory
                 */

                /**
                 * @typedef SFTPTransportType
                 * @augments TransportType
                 * @property {String}          host - emote server's hostname
                 * @property {Number}          [port = 22] - remote server's SFTP port
                 * @property {String}          path - path to backup directory on remote server
                 * @property {String | Number} [timeout = 30] - session timeout
                 * @property {String}          username - remote server account's username
                 * @property {String}          authtype - authorization type
                 * @property {String}          password - remote server account's password (if authtype is password)
                 * @property {String}          privatekey - path to private key file (if authtype is key)
                 * @property {String}          passphrase - private key file's passphrase (if authtype is key)
                 */

                /**
                 * @typedef AmazonS3TransportType
                 * @augments TransportType
                 * @property {String}          [folder] - valid file path, relative to the root directory
                 * @property {String}          bucket - AmazonS3 bucket
                 * @property {String}          aws_access_key_id - AmazonS3 acces key id
                 * @property {String | Number} [timeout = 30] - session timeout
                 * @property {String}          password - AmazonS3 access key password
                 */

                /**
                 * @typedef S3CompatibleTransportType
                 * @augments TransportType
                 * @property {String}          [folder] - valid file path, relative to the root directory
                 * @property {String}          bucket - AmazonS3 bucket
                 * @property {String}          aws_access_key_id - AmazonS3 acces key id
                 * @property {String | Number} [timeout = 30] - session timeout
                 * @property {String}          password - AmazonS3 access key password
                 * @property {String}          host - remote server's hostname
                 */

                /**
                 * @typedef RsyncTransportType
                 * @augments TransportType
                 * @property {String}          host - emote server's hostname
                 * @property {Number}          [port = 22] - remote server's SFTP port
                 * @property {String}          path - path to backup directory on remote server
                 * @property {String}          username - remote server account's username
                 * @property {String}          authtype - authorization type
                 * @property {String}          password - remote server account's password (if authtype is password)
                 * @property {String}          privatekey - path to private key file (if authtype is key)
                 * @property {String}          passphrase - private key file's passphrase (if authtype is key)
                 */

                /**
                 * @typedef WebDAVTransportType
                 * @augments TransportType
                 * @property {String}           host - remote server's host name
                 * @property {Number}           [port = 21] - remote server's FTP port
                 * @property {String}           path - the path to the backups directory on remote server
                 * @property {String | Boolean} [ssl = 1] - whether to use SSL
                 * @property {String | Number}  [timeout = 30] - session timeout
                 * @property {String}           username - remote server account's username
                 * @property {String}           password - remote server account's password
                 */

                /**
                 * @typedef BackblazeB2TransportType
                 * @augments TransportType
                 * @property {String}           path - the path to the backups directory on remote server
                 * @property {String | Number}  [timeout = 30] - session timeout
                 * @property {String}           bucket_id - unique identifier for named bucket
                 * @property {String}           bucket_name - unique name for bucket on Backblaze server
                 * @property {String}           application_key_id - unique identifier for Backblaze application
                 * @property {String}           application_key - secret key for Backblaze application
                 */

                /**
                 * @typedef SSHKeyConfigType
                 * @property {String}           [user = root] - key's owner
                 * @property {String}           [passphrase] - key's passphrase
                 * @property {String}           [name = id_rsa | id_dsa] - key's file name, default depends on algorithm chosen
                 * @property {Number}           [bits = 4096 | 1024] - key's bits, default depends on algorithm chosen (RSA = 4096, DSA = 1024)
                 * @property {String}           [algorithm = system default] - key's encryption algorithm, defaults to system default
                 * @property {String | Boolean} abort_on_existing_key = 1 - whether to abort the function if user already has key, always set to 1 (true)
                 * @property {String}           [comment] - a comment
                 */

                /**
                 * Parses raw response for consumption by front end
                 *
                 * @private
                 * @method parseConfigData
                 * @param   {BackupConfiguration} response - raw response from API
                 * @returns {BackupConfiguration}  parsed data for consumption by front end
                 */
                function parseConfigData(response) {
                    var data = response.data.backup_config;

                    for (var i = 0, len = BOOLEAN_PROPERTIES.length; i < len; i++) {
                        var boolProperty = BOOLEAN_PROPERTIES[i];
                        data[boolProperty] = PARSE.parsePerlBoolean(data[boolProperty]);
                    }

                    for (var j = 0, len = NUMBER_PROPERTIES.length; j < len; j++) { // eslint-disable-line no-redeclare
                        var numProperty = NUMBER_PROPERTIES[j];
                        data[numProperty] = parseInt(data[numProperty], 10);
                    }

                    for (var k = 0, len = NUM_STRING_PROPERTIES.length; k < len; k++) { // eslint-disable-line no-redeclare
                        var property = NUM_STRING_PROPERTIES[k];
                        var numbers = data[property].split(",");
                        data[property] = {};
                        numbers.forEach(function(number) {
                            data[property][number] = number;
                        });
                    }

                    configService.settings = data;

                    return configService.settings;
                }

                /**
                 * Parses raw transports response for consumption by front end
                 *
                 * @private
                 * @method parseDestinations
                 * @param {Array.<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>} response - array of raw transport objects
                 *   @property {String | Boolean} destination.disabled - Perl boolean, which is a string, to be parsed into JavaScript boolean (enabled = true, disabled = false)
                 *   @property {String | Boolean} destination.upload_system_backup - String to be parsed into JavaScript Boolean
                 *   @property {String | Boolean} destination.only_used_for_logs - String to be parsed into JavaScript Boolean
                 * @returns {Array.<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} array of parsed transport objects for consumption by front end
                 */
                function parseDestinations(response) {
                    var destinations = response.data;
                    var parsedDestinations = [];

                    destinations.forEach(function(destination) {
                        destination.disabled = PARSE.parsePerlBoolean(destination.disabled);
                        destination.upload_system_backup = PARSE.parsePerlBoolean(destination.upload_system_backup);
                        destination.only_used_for_logs = PARSE.parsePerlBoolean(destination.only_used_for_logs);

                        parsedDestinations.push(destination);
                    });

                    configService.destinations = parsedDestinations;
                    return configService.destinations;
                }

                /**
                 * Parses raw transport response for consumption by front end
                 *
                 * @private
                 * @method parseDestination
                 * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>} response - raw destination response object
                 * @returns {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} array of parsed transport objects for consumption by front end
                 */
                function parseDestination(response) {
                    var destination = response.data;
                    var type = destination.type.toLowerCase();
                    var parsedDestination = {};
                    parsedDestination[type] = {};

                    destination.disabled = PARSE.parsePerlBoolean(destination.disabled);
                    destination.upload_system_backup = PARSE.parsePerlBoolean(destination.upload_system_backup);
                    destination.only_used_for_logs = PARSE.parsePerlBoolean(destination.only_used_for_logs);

                    if (destination.timeout) {
                        destination.timeout = parseInt(destination.timeout, 10);
                    }

                    if (destination.passive) {
                        destination.passive = PARSE.parsePerlBoolean(destination.passive);
                    }

                    if (destination.port) {
                        destination.port = parseInt(destination.port, 10);
                    }

                    if (destination.mount) {
                        destination.mount = PARSE.parsePerlBoolean(destination.mount);
                    }

                    if (destination.ssl) {
                        destination.ssl = PARSE.parsePerlBoolean(destination.ssl);
                    }

                    for (var prop in destination) {
                        if (destination.hasOwnProperty(prop)) {
                            parsedDestination[type][prop] = destination[prop];
                        }
                    }
                    return parsedDestination;
                }

                /**
                 * Transforms data structure of transport
                 *
                 * @private
                 * @method serializeDestinations
                 * @param   {CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType} data parsed data object
                 * @returns {CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType} serialized object for API consumption
                 */
                function serializeDestination(data) {
                    var serializedDestination;

                    for (var prop in data) {
                        if (data.hasOwnProperty(prop)) {
                            serializedDestination = data[prop];
                        }
                    }
                    return serializedDestination;
                }

                /**
                 * Transforms objects into strings
                 *
                 * @private
                 * @method serializeProperty
                 * @param  {Object} parsed configuration property that must be formatted as string
                 * @returns {String} serialized property for consumption by API
                 */
                function serializeProperty(data) {
                    var propertyString = "";
                    for (var prop in data) {
                        if (data.hasOwnProperty(prop)) {
                            propertyString += data[prop] + ",";
                        }
                    }
                    return propertyString.substring(0, propertyString.length - 1);
                }

                /**
                 * Add parameters to API request for adding or updating an
                 * additional destination.
                 *
                 * @private
                 * @method buildDestinationAPICall
                 * @param  {Object} encapsulates destination info and APIRequest instance
                 */
                function buildDestinationAPICall(requestInfo) {
                    var serializedDestination = requestInfo.destination;
                    var apiRequest = requestInfo.apiCall;

                    apiRequest.addArgument("id", serializedDestination.id);
                    apiRequest.addArgument("name", serializedDestination.name);
                    apiRequest.addArgument("type", serializedDestination.type);
                    apiRequest.addArgument("disabled", serializedDestination.disabled ? 1 : 0);
                    apiRequest.addArgument("upload_system_backup", serializedDestination.upload_system_backup ? 1 : 0);
                    apiRequest.addArgument("only_used_for_logs", serializedDestination.only_used_for_logs ? 1 : 0);

                    if (serializedDestination.destination !== "Local" && serializedDestination.timeout) {
                        apiRequest.addArgument("timeout", serializedDestination.timeout);
                    }

                    if ((serializedDestination.type === "FTP" ||
                        serializedDestination.type === "SFTP" ||
                        serializedDestination.type === "Rsync" ||
                        serializedDestination.type === "WebDAV") &&
                        serializedDestination.port) {
                        apiRequest.addArgument("port", serializedDestination.port);
                    }

                    if (serializedDestination.type === "Custom") {
                        apiRequest.addArgument("script", serializedDestination.script);
                        apiRequest.addArgument("host", serializedDestination.host);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("username", serializedDestination.username);
                        apiRequest.addArgument("password", serializedDestination.password);
                    }

                    if (serializedDestination.type === "FTP") {
                        apiRequest.addArgument("host", serializedDestination.host);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("passive", serializedDestination.passive ? 1 : 0);
                        apiRequest.addArgument("username", serializedDestination.username);
                        apiRequest.addArgument("password", serializedDestination.password);
                    }

                    if (serializedDestination.type === "GoogleDrive") {
                        apiRequest.addArgument("client_id", serializedDestination.client_id);
                        apiRequest.addArgument("client_secret", serializedDestination.client_secret);
                        apiRequest.addArgument("folder", serializedDestination.folder);
                    }

                    if (serializedDestination.type === "Local") {
                        apiRequest.addArgument("mount", serializedDestination.mount ? 1 : 0);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("no_mount_fail", serializedDestination.no_mount_fail);
                    }

                    if (serializedDestination.type === "AmazonS3" || serializedDestination.type === "S3Compatible") {
                        apiRequest.addArgument("folder", serializedDestination.folder);
                        apiRequest.addArgument("bucket", serializedDestination.bucket);
                        apiRequest.addArgument("aws_access_key_id", serializedDestination.aws_access_key_id);
                        apiRequest.addArgument("password", serializedDestination.password);

                        if (serializedDestination.type === "S3Compatible") {
                            apiRequest.addArgument("host", serializedDestination.host);
                        }
                    }

                    if (serializedDestination.type === "SFTP") {
                        apiRequest.addArgument("host", serializedDestination.host);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("username", serializedDestination.username);
                        apiRequest.addArgument("authtype", serializedDestination.authtype);
                        apiRequest.addArgument("password", serializedDestination.password);
                        apiRequest.addArgument("privatekey", serializedDestination.privatekey);
                        apiRequest.addArgument("passphrase", serializedDestination.passphrase);
                    }

                    if (serializedDestination.type === "Rsync") {
                        apiRequest.addArgument("host", serializedDestination.host);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("username", serializedDestination.username);
                        apiRequest.addArgument("authtype", serializedDestination.authtype);
                        apiRequest.addArgument("password", serializedDestination.password);
                        apiRequest.addArgument("privatekey", serializedDestination.privatekey);
                        apiRequest.addArgument("passphrase", serializedDestination.passphrase);
                    }

                    if (serializedDestination.type === "WebDAV") {
                        apiRequest.addArgument("host", serializedDestination.host);
                        apiRequest.addArgument("path", serializedDestination.path);
                        apiRequest.addArgument("ssl", serializedDestination.ssl ? 1 : 0);
                        apiRequest.addArgument("username", serializedDestination.username);
                        apiRequest.addArgument("password", serializedDestination.password);
                    }

                    if (serializedDestination.type === "Backblaze") {
                        apiRequest.addArgument("application_key", serializedDestination.application_key);
                        apiRequest.addArgument("application_key_id", serializedDestination.application_key_id);
                        apiRequest.addArgument("bucket_id", serializedDestination.bucket_id);
                        apiRequest.addArgument("bucket_name", serializedDestination.bucket_name);
                        apiRequest.addArgument("path", serializedDestination.path);
                    }

                    return apiRequest;
                }

                var BackupConfigurationServices = function() {};


                BackupConfigurationServices.prototype = new APIService();

                angular.extend(BackupConfigurationServices.prototype, {

                    /**
                     * Access point for testing private utility functions.
                     *
                     * @private
                     * @method _testHarness
                     * @param {String} name of utility
                     * @param {Object} data to be massaged or checked
                     **/

                    _testHarness: function(utility, data) {
                        switch (utility) {
                            case "parseDestination":
                                return parseDestination(data);
                            case "parseDestinations":
                                return parseDestinations(data);
                            case "serializeProperty":
                                return serializeProperty(data);
                            case "parseConfigData":
                                return parseConfigData(data);
                            case "serializeDestination":
                                return serializeDestination(data);
                            case "buildDestinationAPICall":
                                return buildDestinationAPICall(data);
                            default:
                                return null;
                        }
                    },

                    /**
                     * Calls WHM API to request current backup configuration
                     *
                     * @async
                     * @method getBackupConfig
                     * @returns {Promise<BackupConfiguration>} deferred.promise - backup configuration object
                     * @throws  {Promise<String>} error message on failure
                     */
                    getBackupConfig: function() {
                        if (configService.settings) {
                            return $q.resolve(configService.settings);
                        } else {
                            var apiRequest = new APIREQUEST.Class();
                            apiRequest.initialize(NO_MODULE, "backup_config_get");
                            var deferred = this.deferred(apiRequest, {
                                transformAPISuccess: parseConfigData,
                            });
                            return deferred.promise;
                        }
                    },

                    /**
                     * Calls WHM API to set new backup config
                     *
                     * @async
                     * @method setBackupConfig
                     * @param {BackupConfiguration} config - An object that has the configuration settings as properties
                     *   @param {Boolean} config.backup_daily_enable - daily backups enabled, converted to Perl boolean
                     *   @param {Boolean} config.backupenable - backups enabled, converted to Perl boolean
                     *   @param {Boolean} config.backup_monthly_enable - monthly backups enabled, converted to Perl boolean
                     *   @param {Boolean} config.backupfiles - backup system files, converted to Perl boolean
                     *   @param {Boolean} config.backupaccts - backup accounts, converted to Perl boolean
                     *   @param {Boolean} config.keeplocal - whether to delete backups from loca directory, converted to Perl boolean
                     *   @param {Boolean} config.localzonesonly - whether to use `/var/named/domain.tld` or dnsadmin, converted to Perl boolean (1 = file, 0 = dnsadmin)
                     *   @param {Boolean} config.backupbwdata - backup bandwidth tracking data, converted to Perl boolean
                     *   @param {Boolean} config.backuplogs - backup error logs, converted to Perl boolean
                     *   @param {Boolean} config.backupsuspendedaccts - backup suspended accounts, converted to Perl boolean
                     *   @param {Boolean} config.backupmount - mount a backup partition, converted to Perl boolean
                     *   @param {Boolean} config.check_min_free_space - check server to ensure minimum space is available, converted to Perl boolean
                     *   @param {Boolean} config.force_prune_daily - prune retained daily backups, converted to Perl boolean
                     *   @param {Boolean} config.force_prune_Weekly - prune retained weekly backups, converted to Perl boolean
                     *   @param {Boolean} config.force_prune_monthly - prune retained monthly backups, converted to Perl boolean
                     *   @param {Boolean} config.backup_weekly_enable - weekly backups enabled, converted to Perl boolean
                     *   @param {Object} config.backupdays - An object to be converted into a string for API consumption
                     *   @param {Object} config.backup_monthly_dates - An object to be converted into a string for API consumption
                     * @returns {Promise<String>} success message
                     * @throws  {Promise<String>} error message on failure
                     */
                    setBackupConfig: function(config) {
                        var apiRequest = new APIREQUEST.Class();
                        apiRequest.initialize(NO_MODULE, "backup_config_set");

                        apiRequest.addArgument("backup_daily_enable", config.backup_daily_enable ? 1 : 0);
                        apiRequest.addArgument("backupenable", config.backupenable ? 1 : 0);
                        apiRequest.addArgument("backup_monthly_enable", config.backup_monthly_enable ? 1 : 0);
                        apiRequest.addArgument("backuptype", config.backuptype);
                        apiRequest.addArgument("backup_daily_retention", config.backup_daily_retention);
                        if (config.backup_daily_enable) {
                            apiRequest.addArgument("backupdays", serializeProperty(config.backupdays));
                        }
                        apiRequest.addArgument("backupfiles", config.backupfiles ? 1 : 0);
                        apiRequest.addArgument("backupaccts", config.backupaccts ? 1 : 0);
                        apiRequest.addArgument("keeplocal", config.keeplocal ? 1 : 0);
                        apiRequest.addArgument("localzonesonly", config.localzonesonly ? 1 : 0);
                        apiRequest.addArgument("backupbwdata", config.backupbwdata ? 1 : 0);
                        apiRequest.addArgument("backuplogs", config.backuplogs ? 1 : 0);
                        apiRequest.addArgument("backupsuspendedaccts", config.backupsuspendedaccts ? 1 : 0);
                        apiRequest.addArgument("backupdir", config.backupdir);
                        apiRequest.addArgument("remote_restore_staging_dir", config.remote_restore_staging_dir);
                        apiRequest.addArgument("backupmount", config.backupmount ? 1 : 0);
                        apiRequest.addArgument("mysqlbackup", config.mysqlbackup);
                        apiRequest.addArgument("backup_monthly_retention", config.backup_monthly_retention);
                        apiRequest.addArgument("check_min_free_space", config.check_min_free_space ? 1 : 0);
                        apiRequest.addArgument("min_free_space", config.min_free_space);
                        apiRequest.addArgument("min_free_space_unit", config.min_free_space_unit);
                        apiRequest.addArgument("force_prune_daily", config.force_prune_daily ? 1 : 0);
                        apiRequest.addArgument("force_prune_weekly", config.force_prune_weekly ? 1 : 0);
                        apiRequest.addArgument("force_prune_monthly", config.force_prune_monthly ? 1 : 0);
                        apiRequest.addArgument("maximum_timeout", config.maximum_timeout);
                        apiRequest.addArgument("maximum_restore_timeout", config.maximum_restore_timeout);
                        apiRequest.addArgument("backup_weekly_enable", config.backup_weekly_enable ? 1 : 0);
                        apiRequest.addArgument("backup_weekly_day", config.backup_weekly_day);
                        apiRequest.addArgument("backup_weekly_retention", config.backup_weekly_retention);

                        if (config.backup_monthly_dates) {
                            apiRequest.addArgument("backup_monthly_dates", serializeProperty(config.backup_monthly_dates));
                        }

                        var deferred = this.deferred(apiRequest);
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to request current list of backup destinations
                     *
                     * @async
                     * @method getDestinationList
                     * @returns {Promise<Array.<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>>} - array of parsed transport object
                     * @throws  {Promise<String>} error message on failure
                     */
                    getDestinationList: function() {
                        if (configService.destinations.length > 0) {
                            return $q.resolve(configService.destinations);
                        } else {
                            var apiRequest = new APIREQUEST.Class();

                            apiRequest.initialize(NO_MODULE, "backup_destination_list");
                            var deferred = this.deferred(apiRequest, {
                                transformAPISuccess: parseDestinations,
                            });
                            return deferred.promise;
                        }
                    },


                    /**
                     * Calls WHM API to validate current backup destination, sets destination to always be disabled if validation fails
                     *
                     * @async
                     * @method validateDestination
                     * @param   {String} id - unique id for destination
                     * @returns {Promise<String>} success message
                     * @throws  {Promise<String>} error message on failure
                     */
                    validateDestination: function(id) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_destination_validate");
                        apiRequest.addArgument("id", id);
                        apiRequest.addArgument("disableonfail", 1);

                        var deferred = this.deferred(apiRequest);
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to delete backup destination
                     *
                     * @async
                     * @method deleteDestination
                     * @param   {String} id - unique id for destination
                     * @returns {Promise<String>} success message
                     * @throws  {Promise<String>} error message on failure
                     */
                    deleteDestination: function(id) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_destination_delete");
                        apiRequest.addArgument("id", id);

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {

                                // delete from cached version of destination list
                                if (configService.destinations.length > 0) {
                                    _.remove(configService.destinations, function(cachedDest) {
                                        return cachedDest.id === id;
                                    });
                                }
                                return response;
                            },
                        });
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to toggle destination enable/disable status
                     *
                     * @async
                     * @method toggleStatus
                     * @param {String} id - unique id for destination
                     * @param {Boolean} disabled - whether destination is enabled or disabled
                     * @returns {Promise<String>} success message
                     * @throws  {Promise<String>} error message on failure
                     */
                    toggleStatus: function(id, disabled) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_destination_set");
                        apiRequest.addArgument("id", id);
                        apiRequest.addArgument("disabled", disabled ? 1 : 0); // convert to Perl boolean

                        var deferred = this.deferred(apiRequest);
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to return destination configuration
                     *
                     * @async
                     * @method getDestination
                     * @param {String} id - unique id for destination
                     * @returns {Promise<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>}
                     * @throws  {Promise<String>} error message on failure
                     */
                    getDestination: function(id) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_destination_get");
                        apiRequest.addArgument("id", id);
                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: parseDestination,
                        });
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to update existing destination configuration
                     *
                     * @async
                     * @method updateCurrentDestination
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>} destination - transport object
                     * @returns {Promise<String>} success message
                     * @throws  {Promise<String>} error message on failure
                     */
                    updateCurrentDestination: function(destination) {
                        var serializedDestination = serializeDestination(destination);
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_destination_set");

                        buildDestinationAPICall({ destination: serializedDestination, apiCall: apiRequest });

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {

                                // get the destination object from the function parameter

                                var destinationTypeKey = Object.keys(destination)[0];
                                var destinationProps = destination[destinationTypeKey];

                                // find corresponding object in the cache

                                var cachedObject = _.find(configService.destinations, function(dest) {
                                    return dest.id === destinationProps.id;
                                });

                                // update object in cache to reflect changes

                                if (cachedObject && typeof destinationProps === "object") {
                                    for (var prop in destinationProps) {
                                        if (destinationProps.hasOwnProperty(prop)) {
                                            cachedObject[prop] = destinationProps[prop];
                                        }
                                    }
                                }

                                return response.data;
                            },
                        });
                        return deferred.promise;
                    },

                    /**
                     * Calls WHM API to create new destination configuration
                     *
                     * @async
                     * @method setNewDestination
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType | BackblazeB2TransportType>} destination - transport object
                     * @returns {Promise<String>} unique ID for newly created destination
                     * @throws  {Promise<String>} error message on failure
                     */
                    setNewDestination: function(destination) {
                        var serializedDestination = serializeDestination(destination);
                        var apiRequest = new APIREQUEST.Class();
                        apiRequest.initialize(NO_MODULE, "backup_destination_add");

                        buildDestinationAPICall({ destination: serializedDestination, apiCall: apiRequest });

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {

                                // add the destination to the cache
                                var newDestination = _.assign({}, destination[Object.keys(destination)[0]], response.data);
                                configService.destinations.push(newDestination);

                                return response.data;
                            },
                        });
                        return deferred.promise;
                    },

                    /**
                     * Generates credentials given a specific client ID and secret
                     *
                     * @async
                     * @method generateGoogleCredentials
                     * @param  {String} clientId - string identifying client, obtained from Google Drive API
                     * @param  {String} clientSecret - unique string, obtained from Google Drive API
                     * @returns {Promise<String>} URI directing user to OAuth page
                     * @throws  {Promise<String>} error message on failure
                     */
                    generateGoogleCredentials: function(clientId, clientSecret) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_generate_google_oauth_uri");
                        apiRequest.addArgument("client_id", clientId);
                        apiRequest.addArgument("client_secret", clientSecret);

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {
                                return response.data;
                            },
                        });
                        return deferred.promise;
                    },

                    /**
                     * Checks if client credentials exists given a specific client ID
                     *
                     * @async
                     * @method checkForGoogleCredentials
                     * @param {String} clientId - unique identifying string of user
                     * @returns {Promise<Boolean>} true if credentials exists, false if they do not
                     * @throws  {Promise<String>} error message on failure
                     */
                    checkForGoogleCredentials: function(clientId) {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "backup_does_client_id_have_google_credentials");
                        apiRequest.addArgument("client_id", clientId);

                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {
                                if (response.data.exists) {
                                    return true;
                                } else {
                                    return false;
                                }
                            },
                        });

                        return deferred.promise;
                    },

                    /**
                     * Creates new SSH key pair
                     *
                     * @async
                     * @method generateSSHKeyPair
                     * @param  {SSHKeyConfigType} keyConfig - object representing SSH key configuration
                     * @param  {String} username - indicates user generating keys, defaults to root
                     * @returns {Promise<Object>}  returns metadata object indicating success
                     * @throws  {Promise<String>}  error message on failure
                     */
                    generateSSHKeyPair: function(keyConfig, username) {
                        var apiRequest = new APIREQUEST.Class();
                        apiRequest.initialize(NO_MODULE, "generatesshkeypair");
                        apiRequest.addArgument("user", username);
                        apiRequest.addArgument("passphrase", keyConfig.passphrase);
                        apiRequest.addArgument("name", keyConfig.name);
                        apiRequest.addArgument("bits", keyConfig.bits);
                        apiRequest.addArgument("algorithm", keyConfig.algorithm === "RSA" ? "rsa2" : "dsa");

                        /**
                         * this parameter always passes as 1, per documentation
                         * https://confluence0.cpanel.net/display/public/SDK/WHM+API+1+Functions+-+generatesshkeypair
                         */
                        apiRequest.addArgument("abort_on_existing_key", 1);
                        apiRequest.addArgument("comment", keyConfig.comment ? keyConfig.comment : "");
                        var deferred = this.deferred(apiRequest);
                        return deferred.promise;
                    },

                    /**
                     * Lists all private keys for the root user
                     *
                     * @async
                     * @method listSSHKeys
                     * @returns {Promise<Array.<String>>} array of strings representing all private SSH keys
                     * @throws  {Promise<String>} error message on failure
                     */
                    listSSHKeys: function() {
                        var apiRequest = new APIREQUEST.Class();

                        apiRequest.initialize(NO_MODULE, "listsshkeys");
                        apiRequest.addArgument("user", "root");
                        apiRequest.addArgument("private", 1);
                        apiRequest.addArgument("public", 0);


                        var deferred = this.deferred(apiRequest, {
                            transformAPISuccess: function(response) {
                                var names = [];
                                response.data.forEach(function(key) {
                                    names.push(key.file);
                                });
                                return names;
                            },
                        });
                        return deferred.promise;

                    },
                });

                return new BackupConfigurationServices();
            },
        ]);
    });
