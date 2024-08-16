/*
# templates/mysqlhost/services/MySQLHostDataSource.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
        "app/models/MysqlProfile",
        "app/models/MysqlProfileUsingSsh"
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER, MysqlProfile, MysqlProfileUsingSsh) {

        // Retrieve the current application
        var app = angular.module("App");

        var mysqlHostData = app.factory("MySQLHostDataSource", ["$q", function($q) {

            var mysqlHostData = {};

            mysqlHostData.profiles = {};

            mysqlHostData.clearCache = function() {
                mysqlHostData.profiles = {};
            };

            mysqlHostData.generateErrorMessageForDisplay = function(metadata) {
                if (!metadata) {
                    return LOCALE.maketext("An unexpected error occurred.");
                }

                var error = _.escape(metadata.reason) + "<br><br>",
                    i = 0,
                    len = metadata.error_count,
                    escapedMessages = [];

                for (i; i < len; i++) {
                    escapedMessages.push(_.escape(metadata.errors[i]));
                }

                error += escapedMessages.join("<br>");

                return error;
            };

            mysqlHostData.createObjectForTransport = function(object) {
                var obj = {};

                if (object instanceof MysqlProfile) {
                    obj = {
                        "name": object.name,
                        "mysql_host": object.host,
                        "mysql_port": object.port,
                        "mysql_user": object.account,
                        "mysql_pass": object.password
                    };
                    if (object.hasOwnProperty("active")) {
                        obj.active = object.active ? 1 : 0;
                    }
                } else if (object instanceof MysqlProfileUsingSsh) {
                    obj = {
                        "name": object.name,
                        "host": object.host,
                        "port": object.port,
                        "user": object.account,
                        "password": object.password,
                        "sshkey_name": object.ssh_key,
                        "sshkey_passphrase": object.ssh_passphrase,
                        "root_escalation_method": object.escalation_type
                    };
                    if (object.hasOwnProperty("active")) {
                        obj.active = object.active ? 1 : 0;
                    }
                    if (object.escalation_type === "su") {
                        obj.root_password = object.escalation_password;
                    }
                }

                return obj;
            };

            mysqlHostData.createObjectFromAPI = function(name, object) {
                var obj = new MysqlProfile({
                    name: name,
                    host: object.mysql_host,
                    port: object.mysql_port,
                    account: object.mysql_user,
                    password: object.mysql_pass,
                    comment: object.setup_via,
                    is_local: object.is_localhost_profile,
                    is_supported: object.mysql_version_is_supported
                });
                var isActive = PARSE.parsePerlBoolean(object.active);
                if (isActive) {
                    obj.activate();
                } else {
                    obj.deactivate();
                }

                return obj;
            };

            mysqlHostData.createObjectsFromAPI = function(data) {
                var profiles = {};
                for (var i = 0, keys = _.keys(data), len = keys.length; i < len; i++) {
                    var name = keys[i];
                    var obj = mysqlHostData.createObjectFromAPI(name, data[keys[i]]);
                    profiles[name] = obj;
                }
                return profiles;
            };

            mysqlHostData.createProfile = function(profileData) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                if (profileData.type === "ssh") {
                    apiCall.initialize("", "remote_mysql_create_profile_via_ssh");
                } else {
                    apiCall.initialize("", "remote_mysql_create_profile");
                }

                var obj = mysqlHostData.createObjectForTransport(profileData);
                for (var i = 0, keys = _.keys(obj), len = keys.length; i < len; i++) {
                    var value = obj[keys[i]];
                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles[response.data.profile_saved] = mysqlHostData.createObjectFromAPI(response.data.profile_saved, response.data.profile_details);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.updateProfile = function(profileData) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "remote_mysql_update_profile");

                var obj = mysqlHostData.createObjectForTransport(profileData);
                for (var i = 0, keys = _.keys(obj), len = keys.length; i < len; i++) {
                    var value = obj[keys[i]];
                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles[response.data.profile_saved] = mysqlHostData.createObjectFromAPI(response.data.profile_saved, response.data.profile_details);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };


            mysqlHostData.loadProfiles = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_read_profiles");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles = mysqlHostData.createObjectsFromAPI(response.data);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.deleteProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_delete_profile");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            delete mysqlHostData.profiles[profileName];
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.validateProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_validate_profile");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data.profile_validated);
                        } else {
                            var errorHtml;

                            errorHtml = mysqlHostData.generateErrorMessageForDisplay(response.meta);
                            errorHtml = mysqlHostData.appendTroubleshootingLink({
                                html: errorHtml,
                                linkId: "validate-troubleshoot-link-" + profileName,
                            });

                            deferred.reject(errorHtml);
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.activateProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_initiate_profile_activation");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data.activation_job_started);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.monitorActivation = function(profileName) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_monitor_profile_activation");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (!response.data.job_in_progress && response.data.last_job_details.status === "FAILED") {
                            deferred.reject(response.data);
                        } else {
                            deferred.resolve(response.data);
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.activationInProgress = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_monitor_profile_activation");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;

                        var activationDetails = {};

                        if (_.isNull(response.data.job_in_progress) && _.isNull(response.data.last_job_details)) {
                            deferred.reject({ in_progress: false });
                        }

                        activationDetails.in_progress = response.data.job_in_progress ? true : false;
                        if (activationDetails.in_progress) {
                            activationDetails.payload = response.data.job_in_progress;
                        } else {
                            activationDetails.payload = response.data.last_job_details;
                        }

                        deferred.resolve(activationDetails);
                    });

                return deferred.promise;
            };

            /**
             * Appends HTML for the troubleshooting link to the end of a growl
             * message's HTML.
             *
             * @method appendTroubleshootingLink
             * @param {object} args
             * @param {string} args.html - The HTML string to which the troubleshooting message should be appended.
             * @param {string} args.linkId - The ID to use on the anchor tag for the link.
             * @returns {string} - The final HTML string, with the troubleshooting message appended.
             */
            mysqlHostData.appendTroubleshootingLink = function(args) {
                var finalHtml = args.html;
                var troubleshootingLinkId = args.linkId;

                var troubleshootingHtml = LOCALE.maketext(
                    "For more information, read our [output,url,_1,documentation,target,_2,id,_3].",
                    "https://go.cpanel.net/troubleshootmysqlprofiles",
                    "troubleshootingDocs",
                    troubleshootingLinkId
                );

                finalHtml += "<div class=\"growl-troubleshooting-link\">" + troubleshootingHtml + "</div>";
                return finalHtml;
            };


            return mysqlHostData;
        }]);

        return mysqlHostData;
    }
);
