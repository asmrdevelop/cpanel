/*
 * backup_configuration/services/backupConfigurationServices.js
 *                                                  Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */
define(
    'app/services/backupConfigurationServices',[
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

/* backup_configuration/services/validationLog.js   Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/validationLog',[

        // Libraries
        "angular",
        "lodash",

        // CJT
        "cjt/core",
        "cjt/util/locale",
        "cjt/services/alertService",
    ],
    function(angular, _, CJT, LOCALE, alertService) {
        "use strict";

        var module = angular.module("whm.backupConfiguration.validationLog.service", []);

        /**
         * Setup validation log service
         */
        module.factory("validationLog", ["$window", "alertService", function($window, alertService) {

            /** List of validation log items for backup destinations. */
            var logEntries = [];

            /* Represents basic information used to record the
             * current validation state for a remote backup destination.
             *
             * @param source {Object} generic destination object or ValidationLogItem
             */
            function ValidationLogItem(source) {
                if (typeof source !== "object") {
                    return;
                }

                // if the source object contains the destinationId
                // property, it is an existing ValidationLogItem,
                // possibly lacking defined methods
                if (source.hasOwnProperty("destinationId")) {
                    this.cloneProperties(source);
                } else {
                    this.name = source.name;
                    this.destinationId = source.id;
                    this.transport = source.type;
                    this.status = "running";
                    this.updateBeginTime();
                }

                if (this.status === "running") {
                    ValidationLogItem.inProgress++;
                }
            }

            /** Static property to allow easy access to log items by destination ID.
             */
            ValidationLogItem.quickAccess = {};

            /** Static property to maintain count of in progress validations.
             *  This avoids excessive looping over the list of validations,
             *  looking for those with a status of "running".
             */
            ValidationLogItem.inProgress = 0;

            /**
             * Update the quick access hash with revised log items (static).
             *
             * @method updateQuickAccess
             * @param newLogItemList {Array} list of log items
             */
            ValidationLogItem.updateQuickAccess = function(newLogItemList) {
                ValidationLogItem.quickAccess = {};
                if (Array.isArray(newLogItemList) && newLogItemList.length > 0) {
                    newLogItemList.forEach(function(item) {
                        if (typeof (item) === "object" &&
                        item.hasOwnProperty("destinationId")) {
                            ValidationLogItem.quickAccess[item.destinationId] = item;
                        }
                    });
                }
            };

            /**
             * Retrieve status from quick access hash.
             *
             * @method getStatusFor
             * @param {string} id - destination id for log item of interest
             * @return {ValidationLogItem}
             */
            ValidationLogItem.getStatusFor = function(id) {
                if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                    return ValidationLogItem.quickAccess[id].status;
                }
                return null;
            };

            /**
             * Given an existing object, copy its properties into this ValidationLogItem.
             * This is used to create complete objects from serialized objects stored in
             * a JSON data structure. JSON does not support methods.
             *
             * @method cloneProperties
             * @param {Object} noFunctionObject
             */
            ValidationLogItem.prototype.cloneProperties = function(noFunctionObject) {
                for (var property in noFunctionObject) {
                    if (noFunctionObject.hasOwnProperty(property)) {
                        this[property] = noFunctionObject[property];
                    }
                }
            };

            /**
             * Update the begin time stamp for a validation run.
             * Also, creates a formatted time for display.
             *
             * @method updateElapsedTime
             */
            ValidationLogItem.prototype.updateBeginTime = function() {
                var start = new Date();
                this.beginTime = Date.now();
                start.setTime(this.beginTime);
                this.formattedBeginTime = start.toLocaleTimeString();
            };

            /**
             * Reset the elapsed time validation log item.
             *
             * @method resetElapsedTime
             */
            ValidationLogItem.prototype.resetElapsedTime = function() {
                delete this.endTime;
                delete this.elapsedTime;
                delete this.alert;
                delete this.formattedElapsedTime;
                this.status = "running";
                ValidationLogItem.inProgress++;
            };

            /**
             * Generate the elapsed time for a completed validation run.
             * Also, creates a formatted string for display purposes.
             *
             * @method generateElapsedTime
             */
            ValidationLogItem.prototype.generateElapsedTime = function() {
                this.endTime = Date.now();
                this.elapsedTime = this.endTime - this.beginTime;
                this.formattedElapsedTime = LOCALE.maketext("[_1] [numerate,_1,second,seconds]", Math.round(this.elapsedTime / 1000));
            };

            /**
             * Updates a ValidationLogItem to indicate that the in progress
             * validation has completed.
             *
             * @method markAsComplete
             */
            ValidationLogItem.prototype.markAsComplete = function(alert) {
                this.generateElapsedTime();
                if (alert.type === "success") {
                    this.status = "success";
                } else {
                    this.status = "failure";
                }

                ValidationLogItem.inProgress--;

                this.alert = alert;
            };

            /**
             * Adds a ValidationLogItem to an existing array. If the item
             * already exists, it is reset to initial settings.
             *
             * @method addTo
             * @param {Array} itemList - array to which to add log item.
             * @return {boolean} true = suceesfully added; false = already there or parameter is not
             * an array
             */
            ValidationLogItem.prototype.addTo = function(itemList) {
                if (Array.isArray(itemList)) {
                    if (!ValidationLogItem.quickAccess.hasOwnProperty(this.destinationId)) {
                        itemList.push(this);
                        ValidationLogItem.quickAccess[this.destinationId] = this;
                        return true;
                    } else {
                        this.status = "running";
                        this.updateBeginTime();
                        this.resetElapsedTime();
                    }
                }
                return false;
            };

            // return the factory interface
            return {

                /**
                 * Get the list of validation log entries.
                 *
                 * @method getLogEntries
                 * @return {array} - array of validation log entries
                 */
                getLogEntries: function() {
                    if (logEntries.length === 0) {

                        // check to see whether there is there is a session cache of validation log entries
                        var sessionCache = $window.sessionStorage.getItem("destination_validation_log");
                        if (sessionCache) {
                            var cachedLogEntries = JSON.parse(sessionCache);
                            cachedLogEntries.forEach(function(entry) {
                                logEntries.push(new ValidationLogItem(entry));
                            });
                        }
                        ValidationLogItem.updateQuickAccess(logEntries);
                    }
                    return logEntries;
                },

                /**
                 * Create a cache of the validation log items using sessionStorage.
                 *
                 * @method cacheLogEntries
                 */
                cacheLogEntries: function() {
                    $window.sessionStorage.setItem("destination_validation_log", JSON.stringify(logEntries));
                },

                /**
                 * Clear the cache of the validation log items stored in sessionStorage.
                 *
                 * @method clearCache
                 */
                clearCache: function() {
                    $window.sessionStorage.removeItem("destination_validation_log");
                },

                /**
                 * Are there entries in the validation log.
                 *
                 * @method hasLogEntries
                 * @return {boolean} - true if populated; false if not
                 */
                hasLogEntries: function() {
                    return logEntries && logEntries.length > 0;
                },

                /**
                 * Update name for a given Id. Called when
                 * updating a destination in case of potential changes affecting
                 * a validation log record.
                 *
                 * @method updateValidationInfo
                 * @param {string} destinationId - unique id of destination that was changed
                 * @param {string} newName - potentially updated name
                 */
                updateValidationInfo: function(destinationId, newName) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(destinationId)) {
                        ValidationLogItem.quickAccess[destinationId].name = _.escape(newName);
                    }
                },

                /**
                 * Add new validation information to the log for a given destination.
                 *
                 * @method add
                 * @param {Object} - validatingDestination the destination being validated
                 */
                add: function(validatingDestination) {
                    var validating = null;
                    if (ValidationLogItem.quickAccess.hasOwnProperty(validatingDestination.id)) {
                        validating = ValidationLogItem.quickAccess[validatingDestination.id];
                        validating.resetElapsedTime();
                        validating.updateBeginTime();
                    } else {
                        validating = new ValidationLogItem(validatingDestination);
                        validating.addTo(logEntries);
                        ValidationLogItem.quickAccess[validating.destinationId] = validating;
                    }
                    this.cacheLogEntries();
                },

                /**
                 * Remove validation information from the log for a given destination.
                 *
                 * @method remove
                 * @param {string} - destinationId - the destination id to remove from the log
                 */
                remove: function(destId) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(destId)) {
                        var itemToRemove = ValidationLogItem.quickAccess[destId];
                        if (itemToRemove.status === "running") {
                            ValidationLogItem.inProgress--;
                        }
                        delete ValidationLogItem.quickAccess[destId];
                        _.remove(logEntries, function(item) {
                            return item.destinationId === destId;
                        });
                        this.cacheLogEntries();
                    }
                },

                /**
                * Is validation in progress for given destination.
                *
                * @method isValidationInProgressFor
                * @param {String} id - id of specific destination to test
                * @returns {Boolean} is destination being validated
                */
                isValidationInProgressFor: function(destination) {
                    if (ValidationLogItem.getStatusFor(destination.id) === "running") {
                        return true;
                    }

                    return false;
                },

                /**
                * Determine whether a validation process is current running.
                *
                * @method isValidationRunning
                * @returns {Boolean} is validation (multiple or single) process running
                */
                isValidationRunning: function() {
                    return ValidationLogItem.inProgress > 0;
                },

                /**
                * Get count of inProgress validations.
                *
                * @method getInProgressCount
                * @returns {number} the current count of in progress validations.
                */
                getInProgressCount: function() {
                    return ValidationLogItem.inProgress;
                },

                /**
                * Gets the current status of the validation process
                * for a given destination id.
                *
                * @method validateAllStatus
                * @param {String} id - unique identification string
                * @return {String} - status string (running | success | failure)
                */
                validateAllStatus: function(id) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                        return ValidationLogItem.quickAccess[id].status;
                    }
                    return null;
                },

                /**
                * Checks whether the validation process for a particular
                * destination succeeded.
                *
                * @method validateAllSuccessFor
                * @param {String} id - unique identification string
                */
                validateAllSuccessFor: function(id) {
                    return this.validateAllStatus(id) === "success";
                },

                /**
                * Checks whether the validation process for a particular
                * destination failed.
                *
                * @method validateAllFailureFor
                * @param {String} id - unique identification string
                */
                validateAllFailureFor: function(id) {
                    return this.validateAllStatus(id) === "failure";
                },

                /**
                * Updates the status of an existing Validation Log Item.
                *
                * @method markAsComplete
                * @param {String} id - unique identification string
                * @param {Object} alertOptions - details of validation result
                */
                markAsComplete: function(id, alertOptions) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id)) {
                        ValidationLogItem.quickAccess[id].markAsComplete(alertOptions);
                        this.cacheLogEntries();
                    }
                },

                /**
                 * Displays alert message for validation result
                 *
                 * @method showValidationMessageFor
                 * @param {String} id - unique identification string
                 */
                showValidationMessageFor: function(id) {
                    if (ValidationLogItem.quickAccess.hasOwnProperty(id) && ValidationLogItem.quickAccess[id].hasOwnProperty("alert")) {
                        alertService.add(ValidationLogItem.quickAccess[id].alert);
                    }
                },
            };
        }]);
    }
);

/*
# backup_configuration/directives/formValidator.js   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/directives/formValidator',[
        "angular",
        "cjt/util/locale",
        "cjt/validator/validator-utils",
        "cjt/validator/domain-validators",
        "cjt/validator/path-validators",
        "cjt/validator/ip-validators",
        "cjt/validator/validateDirectiveFactory"
    ],
    function(angular, LOCALE, validationUtils, domainValidators, pathValidators, ipValidators) {
        "use strict";

        /* regular expressions used by validation checks */
        var loopbackRegex = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
        var protocolRegex = /^http(s)*:\/*/;
        var portRegex = /:\d*$/;
        var bucketRegex = /^[a-z0-9-]*$/;
        var bucketRegexAmazon = /^[a-z0-9-.]*$/;
        var bucketRegexB2 = /^[A-Za-z0-9-]*$/;
        var bucketBeginRegex = /^[-]/;
        var bucketEndRegex = /[-]$/;
        var bucketBeginRegexAmazon = /^[-.]/;
        var bucketEndRegexAmazon = /[-.]$/;
        var bucketBeginB2 = /^b2-/i;


        /* validation messages */
        var relativePathWarning = LOCALE.maketext("You must enter a relative path.");
        var subordinatePathWarning = LOCALE.maketext("You must enter a path within the user home directory.");
        var loopbackWarning = LOCALE.maketext("You cannot enter a loopback address for the remote address.");
        var noSlashesWarning = LOCALE.maketext("You must enter a value without slashes.");
        var noSpacesWarning = LOCALE.maketext("You must enter a value without spaces.");
        var noProtocolAllowedWarning = LOCALE.maketext("The remote host address must not contain a protocol.");
        var noPathWarning = LOCALE.maketext("The remote host address must not contain path information.");
        var noPortWarning = LOCALE.maketext("The remote host address must not contain a port number.");
        var absolutePathWarning = LOCALE.maketext("You must enter an absolute path.");
        var remoteHostWarning = LOCALE.maketext("The remote host address must be a valid hostname or IP address.");
        var bucketLengthWarning = LOCALE.maketext("The bucket name must be between [numf,3] and [numf,63] characters.");
        var b2BucketLengthWarning = LOCALE.maketext("The bucket name must be between [numf,6] and [numf,50] characters.");
        var bucketNameWarning = LOCALE.maketext("The bucket name must not begin or end with a hyphen.");
        var bucketNameWarningAmazon = LOCALE.maketext("The bucket name must not begin or end with a hyphen or a period.");
        var bucketAllowedCharacters = LOCALE.maketext("The bucket name must only contain numbers, hyphens, and lowercase letters.");
        var bucketAllowedCharactersAmazon = LOCALE.maketext("The bucket name must only contain numbers, periods, hyphens, and lowercase letters.");
        var bucketAllowedCharactersB2 = LOCALE.maketext("The bucket name must only contain numbers, hyphens, and letters.");
        var bucketNameB2Reserved = LOCALE.maketext("The [asis,Backblaze] [asis,B2] bucket name must not begin with “b2-” because [asis,Backblaze] reserves this prefix.");

        var validators = {

            /*
             * Checks to see if a value is a valid backup location.
             *
             * @param {string} val - form value to be evaluated
             * @param {string} arg - optional argument ("absolute") to disable relative path checking
             * @return {ValidationResult} results of the validation
             */
            backupLocation: function(val, arg) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                // allow optional field to be empty
                if (!val) {
                    result.isValid = true;
                } else if (arg !== "absolute" && val.length > 0 && val[0] === "/") {
                    result.add("backupConfigIssue", relativePathWarning);
                } else if (val.substring(0, 3) === "../") {
                    result.add("backupConfigIssue", subordinatePathWarning);
                } else {
                    result = pathValidators.methods.validPath(val);
                }

                return result;
            },

            /* Checks to see if a value is a valid S3, AmazonS3 or B2 bucket name.
             *
             * @param {string} val - form value to be evaluated
             * @param {string} arg - optional transport type ("amazon" if AmazonS3, "b2" if Backblaze b2)
             * @return {ValidationResult} results of the validation
             */
            bucket: function(val, arg) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (arg === "b2" && bucketBeginB2.test(val)) {
                    result.add("backupConfigIssue", bucketNameB2Reserved);
                } else if (arg === "b2" && !bucketRegexB2.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharactersB2);
                } else if (arg === "amazon" && !bucketRegexAmazon.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharactersAmazon);
                } else if (arg !== "amazon" && arg !== "b2" && !bucketRegex.test(val)) {
                    result.add("backupConfigIssue", bucketAllowedCharacters);
                } else if (arg === "amazon" && (bucketBeginRegexAmazon.test(val) || bucketEndRegexAmazon.test(val))) {
                    result.add("backupConfigIssue", bucketNameWarningAmazon);
                } else if (arg !== "amazon" && arg !== "b2" && (bucketBeginRegex.test(val) || bucketEndRegex.test(val))) {
                    result.add("backupConfigIssue", bucketNameWarning);
                } else if (arg === "b2" && (val.length < 6 || val.length > 50)) {
                    result.add("backupConfigIssue", b2BucketLengthWarning);
                } else if (val.length < 3 || val.length > 63) {
                    result.add("backupConfigIssue", bucketLengthWarning);
                } else {
                    result.isValid = true;
                }

                return result;
            },

            /*
             * Checks to see if a value is a valid remote host or ip address.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */

            remoteHost: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                var ipCheck = ipValidators.methods.ipv4(val);

                if (ipCheck.isValid) {

                    if (loopbackRegex.test(val)) {

                        // remote destination should not be a loopback
                        result.add("backupConfigIssue", loopbackWarning);
                        return result;
                    }
                    return ipCheck;
                } else {

                    // if it's not a valid ip address
                    // check the hostname for special conditions

                    if (protocolRegex.test(val)) {
                        result.add("backupConfigIssue", noProtocolAllowedWarning);
                        return result;
                    }

                    if (val.indexOf("/") >= 0 || val.indexOf("\\") >= 0) {
                        result.add("backupConfigIssue", noPathWarning);
                        return result;
                    }

                    if (portRegex.test(val)) {
                        result.add("backupConfigIssue", noPortWarning);
                        return result;
                    }
                }

                var fqdnCheck = domainValidators.methods.fqdn(val);

                if (!ipCheck.isValid && !fqdnCheck.isValid) {
                    result.add("backupConfigIssue", remoteHostWarning);
                    return result;
                }

                return fqdnCheck;
            },

            /*
             * Checks a value for the existence of slashes.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            noslashes: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (val.indexOf("/") < 0 && val.indexOf("\\") < 0) {
                    result.isValid =  true;
                } else {
                    result.add("backupConfigIssue", noSlashesWarning);
                }

                return result;
            },

            /*
             * Checks a value for the existence of spaces.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            nospaces: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = false;

                if (val.indexOf(" ") < 0) {
                    result.isValid =  true;
                } else {
                    result.add("backupConfigIssue", noSpacesWarning);
                }

                return result;
            },

            /*
             * Checks a value for a valid absolute path format.
             *
             * @param {string} val - form value to be evaluated
             * @return {ValidationResult} results of the validation
             */
            fullPath: function(val) {
                var result = validationUtils.initializeValidationResult();
                result.isValid = true;

                // allow optional field to be empty
                if (!val) {
                    return result;
                } else if (val.indexOf("/") !== 0) {

                    // value must start with a forward slash (/)
                    result.isValid = false;
                    result.add("backupConfigIssue", absolutePathWarning);
                } else {
                    result = pathValidators.methods.validPath(val);
                }

                return result;
            }

        };

        // Generate a directive for each validation function
        var validatorModule = angular.module("cjt2.validate");
        validatorModule.run(["validatorFactory",
            function(validatorFactory) {
                validatorFactory.generate(validators);
            }
        ]);

        return {
            methods: validators,
            name: "backupConfigurationValidators",
            description: "Validation library for Backup Configuration.",
            version: 1.0,
        };
    }
);

/*
# backup_configuration/views/config.js             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/config',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/username-validators",
        "cjt/validator/compare-validators",
        "app/services/backupConfigurationServices"
    ],
    function(angular, _, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        // var table = new Table();

        var controller = app.controller(
            "config", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$q",
                "$window",
                "backupConfigurationServices",
                "alertService",
                "$timeout",

                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $q,
                    $window,
                    backupConfigurationServices,
                    alertService,
                    $timeout) {

                    /**
                     * Make a copy of the source backup configuration
                     * and return a reference to it.
                     *
                     * @function cloneConfiguration
                     * @param  {Object} sourceConfig - configuration object to copy
                     * @return {Object} - reference to new copy
                     */
                    var cloneConfiguration = function(sourceConfig) {

                        // first do a shallow copy of the sourceConfig
                        var copyOfConfig = _.clone(sourceConfig);

                        // special case properties not copied by shallow copy
                        if (sourceConfig.hasOwnProperty("backupdays")) {
                            copyOfConfig.backupdays = _.clone(sourceConfig.backupdays);
                        }
                        if (sourceConfig.hasOwnProperty("backup_monthly_dates")) {
                            copyOfConfig.backup_monthly_dates = _.clone(sourceConfig.backup_monthly_dates);
                        }

                        return copyOfConfig;
                    };

                    /**
                     * Fetches current backup configuration.
                     *
                     * @scope
                     * @method getBackupConfiguration
                     */
                    $scope.getBackupConfiguration = function() {
                        alertService.clear();
                        backupConfigurationServices.getBackupConfig()
                            .then(function(configuration) {
                                if (!$scope.initialFormData) {
                                    $scope.formData = cloneConfiguration(configuration);
                                    $scope.initialFormData = cloneConfiguration(configuration);
                                } else {
                                    $scope.formData = cloneConfiguration(configuration);
                                }
                                $scope.backupConfigLoaded = true;
                                $scope.formEnabled = $scope.formData.backupenable;
                                $scope.setMonthlyBackupDays();
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "configuration-loading-error",
                                    closeable: true
                                });

                                // set to true on error so loading dialog is removed
                                $scope.backupConfigLoaded = true;
                            });
                    };

                    /**
                     * Toggle between percent and MB as units of storage
                     *
                     * @scope
                     * @method handleUnitToggle
                     * @param  {String} value - value to toggle
                     */
                    $scope.handleUnitToggle = function(value) {
                        if (value === "%") {
                            $scope.formData.min_free_space_unit = "percent";
                        } else if (value === "MB") {
                            $scope.formData.min_free_space_unit = "MB";
                        } else {
                            throw "DEVELOPER ERROR: value argument has unexpected value: " + value;
                        }
                    };

                    /**
                     * Add or remove day from list of active backup days
                     *
                     * @scope
                     * @method handleDaysToggle
                     * @param  {Number} index - index of toggled day in array of days
                     * @param {FormController} form - the form calling the function
                     */
                    $scope.handleDaysToggle = function(index, form) {
                        if ($scope.formData.backupdays[index]) {
                            delete $scope.formData.backupdays[index];
                        } else {
                            $scope.formData.backupdays[index] = index.toString();
                        }

                        form.$setDirty();

                        // if length of array is zero no days are selected and
                        // warning is displayed
                        $scope.selectedDays = Object.keys($scope.formData.backupdays);
                    };

                    /*
                     * Handles toggle between days when setting weekly backups
                     *
                     * @scope
                     * @method handleDayToggle
                     * @param  {Number} index - index referencing active backup day in
                     * @param {FormController} form - the form calling the function
                     * weekly backup settings
                     */

                    $scope.handleDayToggle = function(index, form) {
                        $scope.formData.backup_weekly_day = index;
                        form.$setDirty();
                    };

                    /**
                     * Handles toggle of monthly backup schedule options
                     *
                     * @scope
                     * @method handleMonthlyToggle
                     * @param  {String} day - day to toggle
                     */
                    $scope.handleMonthlyToggle = function(day) {
                        if (!$scope.formData.backup_monthly_dates) {
                            $scope.formData.backup_monthly_dates = {};
                        }

                        if (day === "first") {
                            if ($scope.formData.backup_monthly_dates[1]) {
                                delete $scope.formData.backup_monthly_dates[1];
                            } else {
                                $scope.formData.backup_monthly_dates[1] = "1";
                            }
                        } else if (day === "fifteenth") {
                            if ($scope.formData.backup_monthly_dates[15]) {
                                delete $scope.formData.backup_monthly_dates[15];
                            } else {
                                $scope.formData.backup_monthly_dates[15] = "15";
                            }
                        } else {
                            throw "DEVELOPER ERROR: value argument has unexpected value: " + day;
                        }
                        $scope.setMonthlyBackupDays();
                    };

                    /**
                     * Set boolean values for monthly dates object based on active
                     * backup days
                     *
                     * @scope
                     * @method setMonthlyBackupDays
                     */
                    $scope.setMonthlyBackupDays = function() {
                        if (!$scope.monthlyBackupBool) {
                            $scope.monthlyBackupBool = {};
                        }

                        if ($scope.formData.backup_monthly_dates[1]) {
                            $scope.monthlyBackupBool["first"] = true;
                        } else {
                            $scope.monthlyBackupBool["first"] = false;
                        }

                        if ($scope.formData.backup_monthly_dates[15]) {
                            $scope.monthlyBackupBool["fifteenth"] = true;

                        } else {
                            $scope.monthlyBackupBool["fifteenth"] = false;
                        }

                        if (!$scope.monthlyBackupBool["first"] && !$scope.monthlyBackupBool["fifteenth"]) {
                            delete $scope.formData.backup_monthly_dates;
                        }
                    };

                    /**
                     * Opens new tab with select user options
                     *
                     * @scope
                     * @method redirectToSelectUsers
                     */
                    $scope.redirectToSelectUsers = function() {
                        window.open("../backup_user_selection");
                    };

                    /**
                     * Saves a new backup configuration via API
                     *
                     * @scope
                     * @param {FormController} form - the form calling the function
                     * @method saveConfiguration
                     */
                    $scope.saveConfiguration = function(form) {
                        $scope.saving = true;
                        return backupConfigurationServices.setBackupConfig($scope.formData)
                            .then(function(success) {
                                $scope.initialFormData = cloneConfiguration($scope.formData);
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    message: LOCALE.maketext("The system successfully saved the backup configuration."),
                                    id: "save-configuration-succeeded"
                                });

                                // on success force form to clean state
                                form.$setPristine();
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "save-configuration-failed"
                                });
                            })
                            .finally(function() {
                                $scope.saving = false;
                            });
                    };

                    /**
                     * Resets config page to initial values and scrolls to top of page
                     *
                     * @scope
                     * @method resetConfiguration
                     * @param {FormController} form - the form calling the function
                     */
                    $scope.resetConfiguration = function(form) {

                        $scope.formData = cloneConfiguration($scope.initialFormData);

                        // disable form controls if backups are disabled
                        $scope.enableBackupConfig();

                        // update selectedDays array so validation message is correctly displayed
                        $scope.selectedDays = Object.keys($scope.formData.backupdays);

                        // massage monthly backup days checkboxes
                        $scope.setMonthlyBackupDays();
                        form.$setPristine();

                        $location.hash("backup_status");
                        $anchorScroll();
                    };

                    /**
                     * Handles backup enable toggle and sets scope property to remove
                     * focus from all inputs if backup is not enabled
                     *
                     * @scope
                     * @method enableBackupConfig
                     */
                    $scope.enableBackupConfig = function() {
                        if (!$scope.formData.backupenable) {
                            $scope.formEnabled = false;
                        } else {
                            $scope.formEnabled = true;
                        }
                    };

                    /**
                     * Prevent typing of decimal points (periods) in field
                     *
                     * @scope
                     * @method noDecimalPoints
                     * @param {keyEvent} key event associated with key down
                     */

                    $scope.noDecimalPoints = function(keyEvent) {

                        // keyEvent is jQuery wrapper for KeyboardEvent
                        // better to look at properties in wrapped event
                        var actualEvent = keyEvent.originalEvent;

                        // future proofing: "key" is better property to use
                        // but is not completely supported
                        if ((actualEvent.hasOwnProperty("key") && actualEvent.key === ".") ||
                            (actualEvent.keyCode === 190)) {
                            keyEvent.preventDefault();
                        }
                    };

                    /**
                     * Prevent pasting of non-numbers in field
                     *
                     * @scope
                     * @method onlyNumbers
                     * @param {clipboardEvent} clipboard event associated with paste
                     */

                    $scope.onlyNumbers = function(pasteEvent) {
                        var pastedData = pasteEvent.originalEvent.clipboardData.getData("text");

                        if (!pastedData.match(/[0-9]+/)) {
                            pasteEvent.preventDefault();
                        }
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.backupConfigLoaded = false;

                        $scope.getBackupConfiguration();

                        $scope.dailyDays = [
                            LOCALE.maketext("Sunday"),
                            LOCALE.maketext("Monday"),
                            LOCALE.maketext("Tuesday"),
                            LOCALE.maketext("Wednesday"),
                            LOCALE.maketext("Thursday"),
                            LOCALE.maketext("Friday"),
                            LOCALE.maketext("Saturday")
                        ];
                        $scope.weeklyDays = [
                            LOCALE.maketext("Sunday"),
                            LOCALE.maketext("Monday"),
                            LOCALE.maketext("Tuesday"),
                            LOCALE.maketext("Wednesday"),
                            LOCALE.maketext("Thursday"),
                            LOCALE.maketext("Friday"),
                            LOCALE.maketext("Saturday")
                        ];
                        $scope.absolutePathRegEx = /^\/./;
                        $scope.relativePathRegEx = /^\w./;
                        $scope.remoteHostValidation = /^[a-z0-9.-]{1,}$/i;
                        $scope.remoteHostLoopbackValue = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
                        $scope.disallowedPathChars = /[\\?%*:|"<>]/g;

                        $scope.validating = false;
                        $scope.toggled = true;
                        $scope.saving = false;
                        $scope.deleting = false;
                        $scope.updating = false;
                        $scope.showDeleteConfirmation = false;
                        $scope.destinationName = "";
                        $scope.destinationId = "";
                        $scope.activeTab = 0;
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# backup_configuration/views/destinations.js       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/destinations',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/username-validators",
        "cjt/validator/compare-validators",
        "app/services/backupConfigurationServices",
        "app/services/validationLog"
    ],
    function(angular, _, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        var table = new Table();

        var controller = app.controller(
            "destinations", [
                "$scope",
                "$location",
                "$q",
                "$window",
                "backupConfigurationServices",
                "alertService",
                "$timeout",
                "validationLog",

                function(
                    $scope,
                    $location,
                    $q,
                    $window,
                    backupConfigurationServices,
                    alertService,
                    $timeout,
                    validationLog) {

                    /**
                     * Sets delete confirmation callout element to show and assigns
                     * destination properties to the $scope to be used when deleting destination
                     *
                     * @scope
                     * @method setupDeleteConfirmation
                     * @param {String} name - name of specific destination
                     * @param {String} id - unique identification string
                     */
                    $scope.setupDeleteConfirmation = function(name, id, index) {
                        $scope.index = index;
                        $scope.showDeleteConfirmation = !$scope.showDeleteConfirmation;
                        $scope.updating = !$scope.updating;
                        $scope.destinationName = name;
                        $scope.destinationId = id;
                    };

                    /**
                     * Handles backup enable toggle and sets scope property to remove
                     * focus from all inputs if backup is not enabled
                     *
                     * @scope
                     * @method enableBackupConfig
                     */
                    $scope.enableBackupConfig = function() {
                        if (!$scope.formData.backupenable) {
                            $scope.formEnabled = false;
                        } else {
                            $scope.formEnabled = true;
                        }
                    };

                    /**
                     * Is validation in progress for given destination.
                     *
                     * @scope
                     * @method isValidationInProgressFor
                     * @param {String} id - id of specific destination to test
                     * @returns {Boolean} is destination being validated
                     */
                    $scope.isValidationInProgressFor = function(destination) {
                        return validationLog.isValidationInProgressFor(destination);
                    };

                    /**
                     * Determine whether a validation process is current running.
                     *
                     * @scope
                     * @method isValidationRunning
                     * @returns {Boolean} is validation (multiple or single) process running
                     */
                    $scope.isValidationRunning = function() {
                        return validationLog.isValidationRunning();
                    };

                    /**
                     * Validates destination via API
                     *
                     * @scope
                     * @method validateDestination
                     * @param {String} id - id of specific destination to send to API
                     * @param {String} name - name of specific destination
                     * @param {Object} opts - options
                     * @param {Boolean} opts.all - if true dont clear the alert list since we are validating each destination.
                     * @returns {Promise<String>} - string indicating success
                     * @throws {Promise<String>} - string indicating error
                     */
                    $scope.validateDestination = function(id, name, opts) {
                        if (!opts) {
                            opts = {};
                        }

                        if (!opts.all) {
                            $scope.clearAlerts();
                        }

                        $scope.destinationState.validatingDestination = true;
                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(id);

                        var theDestination = _.find($scope.destinationState.destinationList, function(item) {
                            return item.id === id;
                        });

                        validationLog.add(theDestination);

                        $scope.currentlyValidating = validationLog.getLogEntries();

                        return backupConfigurationServices.validateDestination(id)
                            .then(function(success) {
                                var alertOptions = {
                                    type: "success",
                                    id: "validate-destination-succeeded-" + id,
                                    message: LOCALE.maketext("The validation for the “[_1]” destination succeeded.", _.escape(name)),
                                    closeable: true,
                                    autoClose: 10000,
                                };
                                if (opts.all) {
                                    alertOptions.replace = false;
                                }
                                validationLog.markAsComplete(id, alertOptions);
                                if (!$scope.destinationState.validatingAllDestinations) {
                                    alertService.add(alertOptions);
                                }
                            })
                            .catch(function(error) {
                                var alertOptions = {
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    id: "validate-destination-failed-" + id,
                                };
                                if (opts.all) {
                                    alertOptions.replace = false;
                                }

                                // validation has failed, so mark existing entry in
                                // destinations list as disabled
                                theDestination.disabled = true;

                                validationLog.markAsComplete(id, alertOptions);
                                if (!$scope.destinationState.validatingAllDestinations) {
                                    alertService.add(alertOptions);
                                }
                            })
                            .finally(function() {
                                $scope.destinationState.validatingDestination = $scope.isValidationRunning();
                                $scope.destinationState.showValidationIconHint = true;
                            });
                    };

                    /**
                     * Retrieves all current destinations via API
                     *
                     * @scope
                     * @method getDestinations
                     */
                    $scope.getDestinations = function() {
                        $scope.destinationState.destinationListLoaded = false;
                        return backupConfigurationServices.getDestinationList()
                            .then(function(destinationsData) {
                                $scope.destinationState.destinationList = destinationsData;
                                $scope.destinationState.destinationListLoaded = true;
                                $scope.updating = false;
                                $scope.currentlyValidating = validationLog.getLogEntries();
                                $scope.setPagination(destinationsData);
                            }, function(error) {
                                $scope.destinationState.destinationListLoaded = true;
                                $scope.updating = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "fetch-destinations-failed"
                                });
                            });
                    };

                    /**
                     * Load data and get metadata for table of transports
                     *
                     * @scope
                     * @method setPagination
                     * @param  {Array.<TransportType>} transportData - array of transport objects
                     */
                    $scope.setPagination = function(transportData) {
                        if (transportData) {
                            table.load(transportData);
                            table.setSort("name,type", "asc");

                            // the next two lines should be removed if
                            // pagination for the table is implemented
                            table.meta.limit = transportData.length;
                            table.meta.pageSize = transportData.length;
                        }

                        table.update();
                        $scope.meta = table.getMetadata();
                        $scope.filteredDestinationList = table.getList();
                    };

                    $scope.updateTable = function() {
                        $scope.setPagination();
                    };

                    /**
                     * Sets path of destination template to retrieve
                     *
                     * @scope
                     * @method setTemplatePath
                     * @param {String} type - string indicating destination type selected
                     */
                    $scope.setTemplatePath = function(type) {
                        if (type === "Custom") {
                            $scope.templatePath = "views/customTransport.ptt";
                        } else if (type === "FTP") {
                            $scope.templatePath = "views/FTPTransport.ptt";
                        } else if (type === "GoogleDrive") {
                            $scope.templatePath = "views/GoogleTransport.ptt";
                        } else if (type === "Local" || type === "Additional Local Directory") {
                            $scope.templatePath = "views/LocalTransport.ptt";
                        } else if (type === "SFTP") {
                            $scope.templatePath = "views/SFTPTransport.ptt";
                        } else if (type === "Amazon S3" || type === "AmazonS3") {
                            $scope.templatePath = "views/AmazonS3Transport.ptt";
                        } else if (type === "Rsync") {
                            $scope.templatePath = "views/RsyncTransport.ptt";
                        } else if (type === "WebDAV") {
                            $scope.templatePath = "views/WebDAVTransport.ptt";
                        } else if (type === "S3Compatible") {
                            $scope.templatePath = "views/S3CompatibleTransport.ptt";
                        } else if (type === "Backblaze") {
                            $scope.templatePath = "views/B2.ptt";
                        }
                    };

                    /**
                     * Returns custom transport type where required.
                     *
                     * @scope
                     * @method getTransportType
                     * @param {String} type - string indicating destination type
                     * @returns {String} - type formatted for display
                     */
                    $scope.formattedTransportType = function(type) {
                        if (type === "Backblaze") {
                            return "Backblaze B2";
                        } else if (type === "GoogleDrive") {
                            return "Google Drive™";
                        }

                        return type;
                    };

                    /**
                     * Retrieves selected destination via API
                     *
                     * @scope
                     * @method getDestination
                     * @param {String} id - id of selected destination
                     * @param {String} type - type of selected destination
                     */
                    $scope.getDestination = function(id, type) {
                        $scope.destinationState.fetchingDestination = true;
                        $scope.destinationState.newMode = false;
                        $scope.setTemplatePath(type);

                        return backupConfigurationServices.getDestination(id)
                            .then(function(destinationData) {
                                $scope.destinationState.destination = destinationData;
                                $scope.destinationState.destinationMode = true;
                                $scope.destinationState.fetchingDestination = false;
                                $scope.destinationState.editMode = true;

                                if (type === "SFTP" || type === "Rsync") {
                                    $scope.getSSHKeyList();
                                }

                                if (type === "GoogleDrive") {
                                    $scope.checkCredentials(destinationData.googledrive.client_id, destinationData.googledrive.client_secret);
                                }
                            }, function(error) {
                                $scope.destinationState.fetchingDestination = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "fetch-destination-error"
                                });
                            });
                    };

                    /**
                     * Sets template path and creates new destination object
                     *
                     * @scope
                     * @method createNewDestination
                     * @param  {String} type - destination type
                     */
                    $scope.createNewDestination = function(type) {
                        $scope.destinationState.destination = {};
                        $scope.destinationState.editMode = false;
                        $scope.destinationState.newMode = true;
                        $scope.setTemplatePath(type);

                        /**
                         * New destination object created with default values per
                         * https://confluence0.cpanel.net/display/public/SDK/WHM+API+1+Functions+-+backup_destination_add
                         */

                        if (type === "Custom") {
                            $scope.destinationState.destination.custom = {
                                type: type,
                                timeout: 30
                            };
                        } else if (type === "FTP") {
                            $scope.destinationState.destination.ftp = {
                                type: type,
                                port: 21,
                                passive: true,
                                timeout: 30
                            };
                        } else if (type === "GoogleDrive") {
                            $scope.destinationState.destination.googledrive = {
                                type: type,
                                timeout: 30
                            };
                        } else if (type === "Local" || type === "Additional Local Directory") {
                            $scope.destinationState.destination.local = {
                                type: "Local",
                                mount: false
                            };
                        } else if (type === "SFTP") {
                            $scope.destinationState.destination.sftp = {
                                type: type,
                                authtype: "key",
                                port: 22,
                                timeout: 30
                            };
                            $scope.getSSHKeyList();
                        } else if (type === "AmazonS3") {
                            $scope.destinationState.destination.amazons3 = {
                                type: "AmazonS3",
                                timeout: 30
                            };
                        } else if (type === "S3Compatible") {
                            $scope.destinationState.destination.s3compatible = {
                                type: "S3Compatible",
                                timeout: 30
                            };
                        } else if (type === "Rsync") {
                            $scope.destinationState.destination.rsync = {
                                type: type,
                                authtype: "key",
                                timeout: 30,
                                port: 22
                            };
                            $scope.getSSHKeyList();
                        } else if (type === "WebDAV") {
                            $scope.destinationState.destination.webdav = {
                                type: type
                            };
                        } else if (type === "Backblaze") {
                            $scope.destinationState.destination.backblaze = {
                                type: type,
                                timeout: 180
                            };
                        }
                        $scope.destinationState.destinationMode = true;
                    };

                    /**
                     * Saves new destination via API
                     *
                     * @scope
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} destination - object representing destination config
                     * @param {Boolean} [shouldValidate] - whether the destination should also be validated as well as saved
                     * @method saveDestination
                     * @returns {Promise<String>} - id indicating success in case destination also needs to be validated
                     * @throws {Promise<String>} - string indicating error
                     */
                    $scope.saveDestination = function(destination, shouldValidate) {
                        $scope.clearAlerts();
                        $scope.destinationState.savingDestination = true;
                        var property = Object.keys(destination);
                        var destinationName = destination[property[0]]["name"];
                        if ($scope.destinationState.newMode) {
                            return backupConfigurationServices.setNewDestination(destination)
                                .then(function(response) {
                                    $scope.destinationId = response.id;
                                    $scope.destinationState.googleCredentialsGenerated = false;
                                    $scope.destinationState.destinationMode = false;
                                    $scope.destinationState.newMode = false;
                                    alertService.add({
                                        type: "success",
                                        autoClose: 5000,
                                        message: LOCALE.maketext("The system successfully saved the “[_1]” destination.", _.escape(destinationName)),
                                        id: "save-new-destination-success"
                                    });

                                    if (destination[property[0]]["type"] === "GoogleDrive") {
                                        $scope.destinationState.checkCredentialsOnSave = true;
                                        $scope.checkCredentials(destination[property[0]]["client_id"], destination[property[0]]["client_secret"], $scope.destinationState.checkCredentialsOnSave);
                                    }

                                    return $scope.getDestinations();
                                })
                                .then(function() {
                                    if (shouldValidate) {

                                        // pass all=true for options so save message not overwritten by validate message
                                        $scope.validateDestination($scope.destinationId, _.escape(destinationName), { all: true });
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        closeable: true,
                                        message: _.escape(error),
                                        id: "save-new-destination-error"
                                    });
                                })
                                .finally(function() {
                                    $scope.destinationState.savingDestination = false;
                                });
                        } else if ($scope.destinationState.editMode) {
                            return backupConfigurationServices.updateCurrentDestination(destination)
                                .then(function(response) {
                                    $scope.destinationState.editMode = false;
                                    alertService.add({
                                        type: "success",
                                        autoClose: 5000,
                                        message: LOCALE.maketext("The system successfully saved the “[_1]” destination.", _.escape(destinationName)),
                                        id: "edit-destination-success"
                                    });

                                    if (destination[property[0]]["type"] === "GoogleDrive") {
                                        $scope.destinationState.checkCredentialsOnSave = true;
                                        $scope.checkCredentials(destination[property[0]]["client_id"], destination[property[0]]["client_secret"], $scope.destinationState.checkCredentialsOnSave);
                                    }

                                    $scope.destinationState.destinationMode = false;
                                    return $scope.getDestinations();
                                })
                                .then(function() {

                                    // update any existing entry in validation results table to reflect
                                    // potential edits to the name

                                    var editedId = destination[property[0]]["id"];

                                    validationLog.updateValidationInfo(editedId, _.escape(destinationName));

                                    if (shouldValidate) {

                                        // pass all=true for options so save message not overwritten by validate message
                                        $scope.validateDestination(destination[property[0]]["id"], _.escape(destinationName), { all: true });
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        closeable: true,
                                        message: error,
                                        id: "edit-destination-error"
                                    });
                                })
                                .finally(function() {
                                    $scope.destinationState.savingDestination = false;
                                });
                        }

                    };

                    /**
                     * Saves and validates destination, saveDestination resolves
                     * into destination id
                     *
                     * @scope
                     * @method saveAndValiidateDestination
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} destination - object representing destination config
                     */
                    $scope.saveAndValidateDestination = function(destination) {
                        var shouldValidate = true;
                        return $scope.saveDestination(destination, shouldValidate);
                    };

                    /**
                     * Cancels current destination configuration by clearing alerts
                     * and hiding destination view
                     *
                     * @scope
                     * @method cancelDestination
                     */
                    $scope.cancelDestination = function(skipScrolling) {
                        $scope.clearAlerts();

                        $scope.destinationState.destinationMode = false;
                        $scope.destinationState.editMode = false;
                        $scope.destinationState.newMode = false;
                        $scope.destinationState.googleCredentialsGenerated = false;
                        if (!skipScrolling) {
                            document.getElementById("additional_destinations_label").scrollIntoView();
                        }
                    };

                    /**
                     * Delete specific destination and then call getDestinations
                     * to display current list
                     *
                     * @scope
                     * @method deleteDestination
                     */
                    $scope.deleteDestination = function(id) {
                        $scope.deleting = true;
                        $scope.showDeleteConfirmation = false;
                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(id);

                        backupConfigurationServices.deleteDestination(id)
                            .then(function(success) {
                                $scope.deleting = false;

                                // delete existing entry from validation results if one exists
                                validationLog.remove(id);
                                $scope.currentlyValidating = validationLog.getLogEntries();
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "delete-destination-success",
                                    message: LOCALE.maketext("The system successfully deleted the “[_1]” destination.", _.escape($scope.destinationName))
                                });
                                $scope.getDestinations();
                            }, function(error) {
                                $scope.deleting = false;
                                $scope.updating = false;
                                alertService.add({
                                    type: "danger",
                                    id: "delete-destination-failed",
                                    closeable: true,
                                    message: error
                                });
                            });
                    };

                    /**
                     * Toggle status of destination then call getDestinations to show current status
                     *
                     * @scope
                     * @method toggleStatus
                     * @param  {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType>} destination - object representing destination config
                     */
                    $scope.toggleStatus = function(destination) {
                        $scope.toggled = false;
                        $scope.updating = true;

                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(destination.id);

                        var disable,
                            message;
                        if (!destination.disabled) {
                            message = LOCALE.maketext("You disabled the destination “[_1]”.", _.escape(destination.name));
                            disable = true;
                        } else if (destination.disabled) {
                            message = LOCALE.maketext("You enabled the destination “[_1]”.", _.escape(destination.name));
                            disable = false;
                        }

                        return backupConfigurationServices.toggleStatus(destination.id, disable)
                            .then(function(success) {
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "toggle-destination-success",
                                    message: message
                                });
                                destination.disabled = !destination.disabled;
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    id: "toggle-destination-failed",
                                    message: error
                                });
                            })
                            .finally(function() {

                                // toggled set to true so that "in process" message
                                // disappears, error message still visible
                                $scope.toggled = true;
                                $scope.updating = false;
                            });
                    };

                    /**
                     * Validate all current destinations via API
                     *
                     * @scope
                     * @method validateAllDestinations
                     */
                    $scope.validateAllDestinations = function() {
                        $scope.currentlyValidating = [];
                        $scope.destinationState.validatingAllDestinations = true;
                        var promises = [];

                        angular.forEach($scope.destinationState.destinationList, function(destination) {
                            promises.push($scope.validateDestination(destination.id, _.escape(destination.name), {
                                all: true
                            }));
                        });
                        return $q.all(promises).finally(function() {
                            $scope.destinationState.validatingAllDestinations = false;
                            $scope.destinationState.validatingDestination = $scope.isValidationRunning();
                        });
                    };

                    /**
                    * Checks whether the validation process for a particular
                    * destination succeeded.
                    *
                    * @scope
                    * @method validateAllSuccessFor
                    * @param {String} id - unique identification string
                    */
                    $scope.validateAllSuccessFor = function(id) {
                        return validationLog.validateAllSuccessFor(id);
                    };

                    /**
                     * Checks whether the validation process for a particular
                     * destination failed.
                     *
                     * @scope
                     * @method validateAllFailureFor
                     * @param {String} id - unique identification string
                     */
                    $scope.validateAllFailureFor = function(id) {
                        return validationLog.validateAllFailureFor(id);
                    };

                    /**
                    * Displays alert message for validation result
                    *
                    * @scope
                    * @method showValidationMessageFor
                    * @param {String} id - unique identification string
                    */
                    $scope.showValidationMessageFor = function(id) {
                        validationLog.showValidationMessageFor(id);
                    };

                    /**
                     * Generates Google user credentials
                     *
                     * @scope
                     * @method generateCredentials
                     * @param {String} clientId - unique identifying string of user from Google Drive API
                     * @param {String} clientSecret - unique secret string from Google Drive API
                     */
                    $scope.generateCredentials = function(clientId, clientSecret) {

                        $scope.destinationState.generatingCredentials = true;
                        return backupConfigurationServices.generateGoogleCredentials(clientId, clientSecret)
                            .then(function(response) {
                                $scope.destinationState.generatingCredentials = false;
                                alertService.add({
                                    type: "info",
                                    closeable: true,
                                    replace: false,
                                    message: LOCALE.maketext("A new window will appear that will allow you to generate Google® credentials."),
                                    id: "check-google-credentials-popup-" + clientId.substring(0, 6)
                                });
                                $timeout(function() {
                                    $window.open(response.uri, "generate_google_credentials");
                                }, 2000);
                            }, function(error) {
                                $scope.destinationState.generatingCredentials = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    replace: false,
                                    id: "generate-google-credentials-failed-" + clientId.substring(0, 6)
                                });
                            });
                    };

                    /**
                     * Checks is Google user credentials are generated
                     *
                     * @scope
                     * @method checkCredentials
                     * @param  {String}  clientId - unique identifying string of user from Google Drive API
                     * @param  {String}  clientSecret - unique secret string from Google Drive API
                     * @param  {Boolean} checkOnSave - if the credentials should be checked from a save event
                     * @returns {Boolean} - returns false if credentials do not exist to alert user on save event
                     */
                    $scope.checkCredentials = function(clientId, clientSecret, checkOnSave) {
                        return backupConfigurationServices.checkForGoogleCredentials(clientId)
                            .then(function(exists) {
                                if (exists) {
                                    $scope.destinationState.googleCredentialsGenerated = true;
                                } else if (checkOnSave && !exists) {
                                    $scope.destinationState.googleCredentialsGenerated = false;
                                    alertService.add({
                                        type: "warning",
                                        closeable: true,
                                        replace: false,
                                        message: LOCALE.maketext("No [asis,Google Drive™] credentials have been generated for client id, “[_1]” ….", _.escape(clientId.substring(0, 5))) + LOCALE.maketext("You must generate new credentials to access destinations that require this client [asis,ID]."),
                                        id: "no-google-credentials-generated-warning-" + clientId.substring(0, 6)
                                    });
                                } else if (!checkOnSave) {
                                    $scope.generateCredentials(clientId, clientSecret);
                                }
                            }, function(error) {
                                $scope.destinationState.googleCredentialsGenerated = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    group: "failed-during-check-google-credentials-error"
                                });
                            });
                    };

                    /**
                     * Toggles between showing and hiding key generation form
                     *
                     * @scope
                     * @method toggleKeyGenerationForm
                     */
                    $scope.toggleKeyGenerationForm = function() {
                        $scope.destinationState.showKeyGenerationForm = !$scope.destinationState.showKeyGenerationForm;
                    };

                    /**
                     * Creates new SSH key for SFTP transport
                     *
                     * @scope
                     * @method generateKey
                     * @param  {SSHKeyConfigType} keyConfig - object representing key configuration
                     */
                    $scope.generateKey = function(keyConfig) {
                        $scope.destinationState.generatingKey = true;
                        var username;
                        if ($scope.destinationState.destination.sftp) {
                            username = $scope.destinationState.destination.sftp.username;
                        } else if ($scope.destinationState.destination.rsync) {
                            username = $scope.destinationState.destination.rsync.username;
                        }
                        backupConfigurationServices.generateSSHKeyPair(keyConfig, username)
                            .then(function() {
                                $scope.destinationState.generatingKey = false;
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "ssh-key-generation-succeeded",
                                    message: LOCALE.maketext("The system generated the key successfully.")
                                });

                                if ($scope.destinationState.destination.sftp) {
                                    $scope.destinationState.destination.sftp.privatekey = $scope.setPrivateKey(keyConfig.name);
                                } else if ($scope.destinationState.destination.rsync) {
                                    $scope.destinationState.destination.rsync.privatekey = $scope.setPrivateKey(keyConfig.name);
                                }

                                $scope.toggleKeyGenerationForm();
                                $scope.getSSHKeyList();
                            }, function(error) {
                                $scope.destinationState.generatingKey = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "ssh-key-generation-failed"
                                });
                            });
                    };

                    /**
                     * Gets list of all private SSH keys for root user
                     *
                     * @scope
                     * @method getSSHKeyList
                     */
                    $scope.getSSHKeyList = function() {
                        $scope.destinationState.sshKeyListLoaded = false;
                        backupConfigurationServices.listSSHKeys()
                            .then(function(response) {
                                $scope.destinationState.sshKeyListLoaded = true;
                                $scope.destinationState.sshKeyList = response;
                            }, function(error) {
                                $scope.destinationState.sshKeyListLoaded = true;
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "ssh-keys-fetch-failed"
                                });

                            });
                    };

                    /**
                     * Sets private key path when key is chosen from list of keys that currently exist
                     *
                     * @scope
                     * @method setPrivateKey
                     * @param {String} key - name of private key file
                     */
                    $scope.setPrivateKey = function(key) {
                        var keyName = "/root/.ssh/" + key;
                        if ($scope.destinationState.destination.sftp) {
                            $scope.destinationState.destination.sftp.privatekey = keyName;
                        } else if ($scope.destinationState.destination.rsync) {
                            $scope.destinationState.destination.rsync.privatekey = keyName;
                        }

                        var privateKeyField = $window.document.getElementById("private_key");
                        if (typeof privateKeyField !== "undefined") {
                            privateKeyField.select();
                            privateKeyField.focus();
                        }

                        return keyName;
                    };

                    /**
                     * Locks key size at 1024 if algorithm chosen is DSA
                     *
                     * @scope
                     * @method toggleKeyType
                     * @param  {String} algorithm - string indicating what algorithm to use for key generation
                     */
                    $scope.toggleKeyType = function(algorithm) {
                        if (algorithm === "DSA") {
                            this.newSSHKey.bits = "1024";
                            this.destinationState.keyBitsSet = true;

                            if (!this.newSSHKey.name || this.newSSHKey.name === "") {
                                this.newSSHKey.name = "id_dsa";
                            }
                        } else if (algorithm === "RSA") {
                            this.newSSHKey.bits = "4096";
                            this.destinationState.keyBitsSet = false;

                            if (!this.newSSHKey.name || this.newSSHKey.name === "") {
                                this.newSSHKey.name = "id_rsa";
                            }
                        }
                    };

                    /**
                     * Clears alerts from all groups
                     *
                     * @scope
                     * @method clearAlerts
                     */
                    $scope.clearAlerts = function() {
                        alertService.clear();
                    };

                    /**
                     * Toggle SSL activation in WebDAV
                     *
                     * @scope
                     * @method toggleSSLWebDAV
                     */
                    $scope.toggleSSLWebDAV = function() {
                        $scope.destinationState.destination.webdav.ssl = !$scope.destinationState.destination.webdav.ssl;
                    };

                    /**
                     * Checks to make sure remote host does not loop back
                     *
                     * @scope
                     * @method checkForLoopBack
                     * @param  {String} host - name of remote host
                     */
                    $scope.checkForLoopBack = function(host) {
                        if (host === $scope.remoteHostLoopbackValue) {
                            $scope.destinationState.isLoopback = true;
                        } else {
                            $scope.destinationState.isLoopback = false;
                        }
                    };

                    /**
                     * Checks backup directory path for invalid characters
                     *
                     * @scope
                     * @method checkForDisallowedChars
                     * @param  {String} path - path to backup directory
                     * @param  {String} chars -string indicating disallowed characters
                     */
                    $scope.checkForDisallowedChars = function(path, chars) {

                        // test will always start at beginning of string
                        chars.lastIndex = 1;
                        var result = chars.test(path);
                        $scope.destinationState.isDisallowedChar = result;
                    };

                    /**
                     * Prevent typing of decimal points (periods) in field
                     *
                     * @scope
                     * @method noDecimalPoints
                     * @param {keyEvent} key event associated with key down
                     */

                    $scope.noDecimalPoints = function(keyEvent) {

                        // keyEvent is jQuery wrapper for KeyboardEvent
                        // better to look at properties in wrapped event
                        var actualEvent = keyEvent.originalEvent;

                        // future proofing: "key" is better property to use
                        // but is not completely supported
                        if ((actualEvent.hasOwnProperty("key") && actualEvent.key === ".") ||
                            (actualEvent.keyCode === 190)) {
                            keyEvent.preventDefault();
                        }
                    };

                    /**
                     * Prevent pasting of non-numbers in field
                     *
                     * @scope
                     * @method onlyNumbers
                     * @param {clipboardEvent} clipboard event associated with paste
                     */

                    $scope.onlyNumbers = function(pasteEvent) {
                        var pastedData = pasteEvent.originalEvent.clipboardData.getData("text");

                        if (!pastedData.match(/[0-9]+/)) {
                            pasteEvent.preventDefault();
                        }
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.absolutePathRegEx = /^\/./;
                        $scope.relativePathRegEx = /^\w./;
                        $scope.remoteHostValidation = /^[a-z0-9.-]{1,}$/i;
                        $scope.remoteHostLoopbackValue = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
                        $scope.disallowedPathChars = /[\\?%*:|"<>]/g;

                        $scope.validating = false;
                        $scope.toggled = true;
                        $scope.saving = false;
                        $scope.deleting = false;
                        $scope.updating = false;
                        $scope.showDeleteConfirmation = false;
                        $scope.destinationName = "";
                        $scope.destinationId = "";
                        $scope.activeTab = 1;
                        $scope.currentlyValidating = validationLog.getLogEntries();

                        $scope.destinationState = {
                            destinationSelected: "Custom",
                            destinationMode: false,
                            savingDestination: false,
                            validatingDestination: $scope.isValidationRunning(),
                            fetchingDestination: false,
                            destinationListLoaded: false,
                            validatingAllDestinations: false,
                            destinationList: [],
                            newMode: false,
                            editMode: false,
                            generatingCredentials: false,
                            googleCredentialsGenerated: false,
                            showKeyGenerationForm: false,
                            generatingKey: false,
                            keyBitsSet: false,
                            sshKeyListLoaded: false,
                            isLoopback: false,
                            isDisallowedChar: false,
                            checkCredentialsOnSave: false,
                            showValidationIconHint: false
                        };

                        if (validationLog.hasLogEntries()) {
                            $scope.destinationState.showValidationIconHint = true;
                        }

                        $scope.meta = {};

                        $scope.displayAlertRows = [];
                        $scope.getDestinations();
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# backup_configuration/views/validationResults.js  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/validationResults',[
        "angular",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/validationLog"
    ],
    function(angular, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        var controller = app.controller(
            "validationResults", [
                "$scope",
                "alertService",
                "validationLog",

                function(
                    $scope,
                    alertService,
                    validationLog) {

                    var logTable = new Table();

                    /**
                     * Sort ValidationLogItem Objects and update table. Items
                     * are sorted in place.
                     *
                     * @scope
                     * @method sortValidationEntries
                     */
                    $scope.sortValidationEntries = function() {
                        $scope.currentlyValidating = logTable.update();
                        $scope.meta = logTable.getMetadata();
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.currentlyValidating = validationLog.getLogEntries();

                        logTable.load($scope.currentlyValidating);

                        logTable.setSort("name,transport", "asc");

                        // remove if pagination is ever implemented
                        logTable.meta.limit = $scope.currentlyValidating.length;
                        logTable.meta.pageSize = $scope.currentlyValidating.length;

                        $scope.$watch("currentlyValidating", function() {
                            $scope.sortValidationEntries();
                            validationLog.cacheLogEntries();
                        }, true);
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# backup_configuration/index.js                    Copyright 2022 cPanel, L.L.C.
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
        "app/services/backupConfigurationServices",
        "app/services/validationLog"
    ],
    function(angular, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.backupConfiguration", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "cjt2.whm",
                "whm.backupConfiguration.backupConfigurationServices.service",
                "whm.backupConfiguration.validationLog.service"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/directives/formValidator",
                    "app/views/config",
                    "app/views/destinations",
                    "app/views/validationResults"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module("whm.backupConfiguration");
                    app.value("PAGE", PAGE);

                    app.controller("BaseController", ["$rootScope", "$scope", "$location",
                        function($rootScope, $scope, $location) {

                            $scope.loading = false;
                            $rootScope.$on("$routeChangeStart", function() {
                                $scope.loading = true;
                                $rootScope.currentRoute = $location.path();
                            });
                        }
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/settings", {
                                controller: "config",
                                templateUrl: "views/config.ptt"
                            });

                            $routeProvider.when("/destinations", {
                                controller: "destinations",
                                templateUrl: "views/destinations.ptt"
                            });

                            $routeProvider.when("/validation", {
                                controller: "validationResults",
                                templateUrl: "views/validationResults.ptt"
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/settings"
                            });
                        }
                    ]);

                    var appContent = angular.element("#pageContainer");
                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        BOOTSTRAP(appContent[0], "whm.backupConfiguration");
                    }

                });

            return app;
        };
    }
);

