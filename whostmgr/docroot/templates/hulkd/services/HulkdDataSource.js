/*
# cpanel - whostmgr/docroot/templates/hulkd/services/HulkdDataSource.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-disable camelcase */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/query",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
    ],
    function(angular, $, _, LOCALE, QUERY, PARSE, API, APIREQUEST, APIDRIVER) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var hulkDataSource = app.factory("HulkdDataSource", ["$q", "PAGE", "COUNTRY_CONSTANTS", function($q, PAGE, COUNTRY_CONSTANTS) {

            var hulkData = {};

            hulkData.whitelist = [];
            hulkData.blacklist = [];

            hulkData.whitelist_comments = {};
            hulkData.blacklist_comments = {};

            hulkData.whitelist_is_cached = false;
            hulkData.blacklist_is_cached = false;

            hulkData.config_settings = {};

            hulkData.enabled = PAGE.hulkd_status.is_enabled;

            hulkData.hulkd_status = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cphulk_status");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        hulkData.enabled = PARSE.parsePerlBoolean(response.data.is_enabled);
                        deferred.resolve(hulkData.enabled);
                    });

                return deferred.promise;
            };

            hulkData.get_countries_with_known_ip_ranges = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_countries_with_known_ip_ranges");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.data);
                    });

                return deferred.promise;
            };

            hulkData.clear_caches = function() {
                hulkData.whitelist = [];
                hulkData.blacklist = [];

                hulkData.whitelist_comments = {};
                hulkData.blacklist_comments = {};

                hulkData.whitelist_is_cached = false;
                hulkData.blacklist_is_cached = false;
            };

            hulkData.enable_hulkd = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "enable_cphulk");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            hulkData.enabled = true;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.disable_hulkd = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "disable_cphulk");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.status);
                            hulkData.enabled = false;

                            // clear the caches to force a reload if
                            // hulkd is re-enabled later
                            hulkData.clear_caches();
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.convert_config_settings = function(config) {
                var settings = {};

                settings.block_brute_force_with_firewall = PARSE.parsePerlBoolean(config.cphulk_config.block_brute_force_with_firewall);
                settings.block_excessive_brute_force_with_firewall = PARSE.parsePerlBoolean(config.cphulk_config.block_excessive_brute_force_with_firewall);
                settings.brute_force_period_mins = config.cphulk_config.brute_force_period_mins;
                settings.command_to_run_on_brute_force = config.cphulk_config.command_to_run_on_brute_force;
                settings.command_to_run_on_excessive_brute_force = config.cphulk_config.command_to_run_on_excessive_brute_force;
                settings.is_enabled = PARSE.parsePerlBoolean(config.cphulk_config.is_enabled);
                settings.ip_brute_force_period_mins = config.cphulk_config.ip_brute_force_period_mins;
                settings.lookback_period_min = config.cphulk_config.lookback_period_min;
                settings.max_failures = config.cphulk_config.max_failures;
                settings.max_failures_byip = config.cphulk_config.max_failures_byip;
                settings.mark_as_brute = config.cphulk_config.mark_as_brute;
                settings.notify_on_root_login = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_root_login);
                settings.notify_on_root_login_for_known_netblock = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_root_login_for_known_netblock);
                settings.notify_on_brute = PARSE.parsePerlBoolean(config.cphulk_config.notify_on_brute);
                settings.can_temp_ban_firewall = PARSE.parsePerlBoolean(config.cphulk_config.can_temp_ban_firewall);
                settings.iptable_error = config.cphulk_config.iptable_error;
                settings.username_based_protection = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection);
                settings.ip_based_protection = PARSE.parsePerlBoolean(config.cphulk_config.ip_based_protection);
                settings.username_based_protection_local_origin = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection_local_origin);
                settings.username_based_protection_for_root = PARSE.parsePerlBoolean(config.cphulk_config.username_based_protection_for_root);

                settings.country_whitelist = config.cphulk_config.country_whitelist ? config.cphulk_config.country_whitelist.split(",") : [];
                settings.country_blacklist = config.cphulk_config.country_blacklist ? config.cphulk_config.country_blacklist.split(",") : [];

                hulkData.config_settings = settings;

                return settings;
            };

            hulkData.save_config_settings = function(config) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "save_cphulk_config");

                for (var i = 0, keys = _.keys(config), len = keys.length; i < len; i++) {

                    // we do not want to send this option
                    if (keys[i] === "is_enabled") {
                        continue;
                    }

                    var value = config[keys[i]];
                    if (_.isArray(value)) {
                        value = value.join(",");
                    } else if (_.isBoolean(value)) {
                        if (value) {
                            value = 1;
                        } else {
                            value = 0;
                        }
                    }

                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // clean up the restart_ssh boolean
                            response.data.restart_ssh = PARSE.parsePerlBoolean(response.data.restart_ssh);
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            hulkData.load_config_settings = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "load_cphulk_config");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response.data,
                                settings = hulkData.convert_config_settings(results);
                            deferred.resolve(settings);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            hulkData.set_cphulk_config_keys = function(updatedKeys) {
                var batchCalls = [];

                angular.forEach(updatedKeys, function(value, key) {
                    batchCalls.push({
                        func: "set_cphulk_config_key",
                        data: {
                            key: key,
                            value: value,
                        },
                    });
                });

                return _batch_apiv1(batchCalls).then(function(results) {

                    // Use the last updated config, giving the most recent cphulk configuration
                    var response = results.pop();
                    response = response.parsedResponse;
                    var settings = hulkData.convert_config_settings(response.data);
                    return hulkData._parse_xlisted_countries(settings);
                });
            };

            function _batch_apiv1(calls_infos) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "batch");

                calls_infos.forEach(function(call, i) {
                    apiCall.addArgument(
                        ("command-" + i),
                        call.func + "?" + QUERY.make_query_string(call.data)
                    );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var results = response.data;
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            }

            hulkData.load_xlisted_countries = function() {
                return hulkData.load_config_settings().then(function(settings) {
                    return hulkData._parse_xlisted_countries(settings);
                });
            };

            hulkData._parse_xlisted_countries = function(settings) {
                var countries = {};
                settings.country_blacklist.forEach(function(item) {
                    countries[item] = COUNTRY_CONSTANTS.BLACKLISTED;
                });
                settings.country_whitelist.forEach(function(item) {
                    countries[item] = COUNTRY_CONSTANTS.WHITELISTED;
                });
                return countries;
            };


            hulkData.add_to_list = function(list, records) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "batch_create_cphulk_records", null, null, { json: true });
                apiCall.addArgument("list_name", list);
                apiCall.addArgument("records", records);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {

                            // on API call success, add to list
                            var return_data = {
                                added: [],
                                rejected: response.data.ips_failed,
                                updated: [],
                            };

                            var original_ips_added = response.data.original_ips_added || [];
                            var ip_list = hulkData[ list + "list" ];
                            var comment_list = hulkData[ list + "list_comments"];

                            for (var i = 0, len = original_ips_added.length; i < len; i++) {

                                var ip = original_ips_added[i];
                                var ip_formatted = response.data.ips_added[i];

                                // Update the ip cache and parse the return data
                                var index = _.indexOf(hulkData.whitelist, ip_formatted);
                                if (index === -1) {
                                    ip_list.push(ip_formatted);
                                    return_data.added.push(ip_formatted);
                                } else {
                                    return_data.updated.push(ip_formatted);
                                }

                                // Update the comment cache.
                                var record = _.find(records, function(record) {
                                    return record.ip === ip;
                                });
                                if (record && record.comment) {
                                    comment_list[ip_formatted] = record.comment;
                                }

                                // Extra info for the whitelist return.
                                if (list === "white") {
                                    return_data.requester_ip = response.data.requester_ip;
                                    return_data.requester_ip_is_whitelisted = response.data.requester_ip_is_whitelisted;
                                }
                            }

                            deferred.resolve(return_data);

                        } else {

                            // pass the error along
                            var error_details = {
                                main_message: response.error,
                                secondary_messages: [],
                            };

                            // Build the reason individual ips were rejected.
                            Object.keys(response.data.ips_failed).forEach(function(ip) {
                                var rejectReason = response.data.ips_failed[ip];
                                error_details.secondary_messages.push(rejectReason);
                            });

                            deferred.reject(error_details);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            hulkData.add_to_whitelist = function(records) {
                return hulkData.add_to_list("white", records);
            };

            hulkData.add_to_blacklist = function(records) {
                return hulkData.add_to_list("black", records);
            };

            hulkData.remove_from_list = function(ips_to_delete, list) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "delete_cphulk_record");
                apiCall.addArgument("list_name", list);
                for (var i = 0; i < ips_to_delete.length; i++) {
                    apiCall.addArgument("ip-" + i, ips_to_delete[i]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var i = 0;

                            if (list === "white") {

                                // remove the IPs
                                hulkData.whitelist = _.difference(hulkData.whitelist, response.data.ips_removed);

                                // remove the comment
                                for (i = 0; i < response.data.ips_removed.length; i++) {
                                    delete hulkData.whitelist_comments[response.data.ips_removed[i]];
                                }
                            } else {

                                // remove the IPs
                                hulkData.blacklist = _.difference(hulkData.blacklist, response.data.ips_removed);

                                // remove the comment
                                for (i = 0; i < response.data.ips_removed.length; i++) {
                                    delete hulkData.blacklist_comments[response.data.ips_removed[i]];
                                }
                            }

                            deferred.resolve({ removed: response.data.ips_removed, not_removed: response.data.ips_failed, requester_ip: response.data.requester_ip, requester_ip_is_whitelisted: response.data.requester_ip_is_whitelisted });
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;

            };

            hulkData.remove_from_whitelist = function(ips_to_delete) {
                return hulkData.remove_from_list(ips_to_delete, "white");
            };

            hulkData.remove_from_blacklist = function(ip_to_delete) {
                return hulkData.remove_from_list(ip_to_delete, "black");
            };

            hulkData.remove_all_from_whitelist = function() {
                return hulkData.remove_from_whitelist(hulkData.whitelist);
            };

            hulkData.remove_all_from_blacklist = function() {
                return hulkData.remove_from_blacklist(hulkData.blacklist);
            };

            hulkData.load_list = function(list) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "read_cphulk_records");
                apiCall.addArgument("list_name", list);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {

                            // on API call success, populate data structure

                            var return_data = {};

                            if (list === "white") {

                                // check to see if the ip address is not whitelisted
                                if (!response.data.requester_ip_is_whitelisted) {
                                    return_data.whitelist_warning = response.data.warning_ip;
                                }
                                if (response.data.restart_ssh) {
                                    return_data.restart_ssh = true;
                                }
                                if (response.data.warning_ssh) {
                                    return_data.warning_ssh = response.data.warning_ssh;
                                }

                                hulkData.whitelist = Object.keys(response.data.ips_in_list).slice();
                                for (var i = 0; i < hulkData.whitelist.length; i++) {
                                    if (response.data.ips_in_list[hulkData.whitelist[i]]) {
                                        hulkData.whitelist_comments[hulkData.whitelist[i]] = response.data.ips_in_list[hulkData.whitelist[i]];
                                    }
                                }
                                hulkData.whitelist_is_cached = true;
                                return_data.list = hulkData.whitelist;
                                return_data.comments = hulkData.whitelist_comments;
                                return_data.requester_ip = response.data.requester_ip;
                                return_data.requester_ip_is_whitelisted = response.data.requester_ip_is_whitelisted;
                                deferred.resolve(return_data);
                            } else if (list === "black") {
                                hulkData.blacklist = Object.keys(response.data.ips_in_list).slice();
                                for (var j = 0; j < hulkData.blacklist.length; j++) {
                                    if (response.data.ips_in_list[hulkData.blacklist[j]]) {
                                        hulkData.blacklist_comments[hulkData.blacklist[j]] = response.data.ips_in_list[hulkData.blacklist[j]];
                                    }
                                }
                                hulkData.blacklist_is_cached = true;
                                return_data.list = hulkData.blacklist;
                                return_data.comments = hulkData.blacklist_comments;
                                return_data.requester_ip = response.data.requester_ip;
                                deferred.resolve(return_data);
                            }
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            function init() {

                // check for page data in the template if this is a first load
                if (app.firstLoad && app.firstLoad.configs && PAGE.config_values) {
                    app.firstLoad.configs = false;
                    hulkData.config_settings = hulkData.convert_config_settings(PAGE.config_values);
                }
            }

            init();

            return hulkData;
        }]);

        return hulkDataSource;
    }
);
