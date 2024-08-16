/*
# convert_addon_to_account/services/Databases.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1" // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var databasesFactory = app.factory("Databases", ["$q", function($q) {

            var db = {};

            db.databases = {};
            db.users = {};
            db.currentOwner = "";

            var uses_prefixing;
            var mysql_version;
            var prefix_length;

            // these are functions that exist in the old cjt/sql.js
            var verify_func_name = {
                mysql: {
                    database: "verify_mysql_database_name"
                },
                postgresql: {
                    database: "verify_postgresql_database_name"
                }
            };

            db.setPrefixing = function(option) {
                uses_prefixing = option;
            };

            db.isPrefixingEnabled = function() {
                return uses_prefixing;
            };

            db.setMySQLVersion = function(version) {
                mysql_version = version;

                // this has to be exported for the old cjt/sql.js to work correctly
                window.MYSQL_SERVER_VERSION = mysql_version;
            };

            db.getMySQLVersion = function() {
                return mysql_version;
            };

            db.setPrefixLength = function(length) {
                prefix_length = length;
            };

            db.getPrefixLength = function() {
                return prefix_length;
            };

            db.createPrefix = function(user) {

                /*
                 * Transfers and some older accounts might have underscores or periods
                 * in the cpusername. For historical reasons, the account's "main" database
                 * username always strips these characters out.
                 * In 99% of cases, this function is a no-op.
                 */
                var username = user.replace(/[_.]/, "");

                var prefixLength = db.getPrefixLength();
                return username.substr(0, prefixLength) + "_";
            };

            db.addPrefix = function(database, user) {
                return db.createPrefix(user) + database;
            };

            db.addPrefixIfNeeded = function(database, user) {
                if (database === void 0 || database === "") {
                    return;
                }

                var prefix = db.createPrefix(user);
                var prefix_regex = new RegExp("^" + prefix + ".+$");

                // if the db already has a prefix, just return it
                if (prefix_regex.test(database)) {
                    return database;
                }

                // else, return the database with the prefix
                return prefix + database;
            };

            /**
             * Transform the data from the API call into a
             * map of users and their corresponding databases.
             *
             * @method createUsersDictionary
             * @param {Object} data - the data returned from the
             * list_mysql_databases_and_users API call
             * return {Object} an object where the keys are db users and values are
             * their associated databases.
             */
            function createUsersDictionary(data) {
                var usersObj = {};
                var user = "";
                var dbs = data.mysql_databases;

                for (var database in dbs) {
                    if (dbs.hasOwnProperty(database)) {
                        for (var i = 0, len = dbs[database].length; i < len; i++) {
                            user = dbs[database][i];
                            if (usersObj.hasOwnProperty(user)) {
                                usersObj[user].push(database);

                            } else {
                                usersObj[user] = [database];
                            }
                        }
                    }
                }

                return usersObj;
            }

            db.listMysqlDbsAndUsers = function(owner) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "list_mysql_databases_and_users");
                apiCall.addArgument("user", owner);

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            db.setPrefixing(PARSE.parsePerlBoolean(response.data.mysql_config.use_db_prefix));
                            db.setPrefixLength(response.data.mysql_config.prefix_length);
                            db.setMySQLVersion(response.data.mysql_config["mysql-version"]);
                            db.databases = response.data.mysql_databases;
                            db.users = createUsersDictionary(response.data);
                        } else {
                            return $q.reject(response.meta);
                        }
                    });
            };

            /**
             * Get the databases from the service. This will call the API
             * if there are no databases stored in the service.
             *
             * @method getDatabases
             * @param {String} owner - the owner of the databases
             * @return {Promise} a promise that resolves to a dictionary of databases for the owner
             */
            db.getDatabases = function(owner) {
                if (Object.keys(db.databases).length > 0 && db.currentOwner === owner) {
                    return $q.when(db.databases);
                } else {
                    return db.listMysqlDbsAndUsers(owner)
                        .then(function() {
                            db.currentOwner = owner;
                            return db.databases;
                        });
                }
            };

            /**
             * Get the users from the service.
             *
             * @method getUsers
             * @return {Object} a dictionary of mysql users
             */
            db.getUsers = function() {
                return db.users;
            };

            db.validateName = function(name, engine) {
                return CPANEL.sql[verify_func_name[engine]["database"]](name);
            };

            return db;
        }]);

        return databasesFactory;
    }
);
