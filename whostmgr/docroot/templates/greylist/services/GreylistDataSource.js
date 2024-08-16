/*
# templates/greylist/services/GraylistDataSource.js Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ], function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("App");

        var greylistDataSource = app.factory("GreylistDataSource", ["$q", "PAGE", function($q, PAGE) {

            var greylistData = {};
            greylistData.trustedHosts = [];

            greylistData.configSettings = {
                is_enabled: PARSE.parsePerlBoolean(PAGE.is_enabled),
                is_exim_enabled: PARSE.parsePerlBoolean(PAGE.is_exim_enabled),
                initial_block_time_mins: parseInt(PAGE.initial_block_time_mins),
                record_exp_time_mins: parseInt(PAGE.record_exp_time_mins),
                must_try_time_mins: parseInt(PAGE.must_try_time_mins),
                spf_bypass: PARSE.parsePerlBoolean(PAGE.spf_bypass),

                DEFAULT: PAGE.config_default,
            };

            greylistData.commonMailProviders = {};

            greylistData.autotrust_new_common_mail_providers = true;

            greylistData.loadCommonMailProviders = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cpgreylist_load_common_mail_providers_config");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var providers = response.data.common_mail_providers;
                            for (var provider in providers) {
                                if (providers[provider].hasOwnProperty("autoupdate") && providers[provider].hasOwnProperty("is_trusted")) {
                                    providers[provider].autoupdate = PARSE.parsePerlBoolean(providers[provider].autoupdate);
                                    providers[provider].is_trusted = PARSE.parsePerlBoolean(providers[provider].is_trusted);
                                }
                            }
                            greylistData.commonMailProviders = response.data.common_mail_providers;
                            greylistData.autotrust_new_common_mail_providers = PARSE.parsePerlBoolean(response.data.autotrust_new_common_mail_providers);
                            deferred.resolve(greylistData);
                        } else {
                            deferred.reject(response);
                        }
                    });

                return deferred.promise;
            };

            greylistData.trustOrUntrustProviders = function(trust, settings) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                var apiFunc = trust ? "cpgreylist_trust_entries_for_common_mail_provider" : "cpgreylist_untrust_entries_for_common_mail_provider";

                apiCall.initialize("", apiFunc);

                var paramIndex = 0;

                for (var provider in settings) {
                    if (settings.hasOwnProperty(provider)) {

                        /* If you are going to trust providers and the provider is currently
                              checked in the UI (trusted), you want to add it to the list of
                              providers to be sent to the trust api call. If you are going to
                              untrust providers and the provider is currently unchecked in the
                              UI (untrusted), you want to add it to the list of providers to
                              be sent to the untrust api call. */
                        if (trust && settings[provider].is_trusted) {
                            apiCall.addArgument("provider-" + paramIndex, provider);
                            paramIndex++;
                        } else if (!trust && !settings[provider].is_trusted) {
                            apiCall.addArgument("provider-" + paramIndex, provider);
                            paramIndex++;
                        }
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            var providers = trust ? Object.keys(response.data.providers_trusted) : Object.keys(response.data.providers_untrusted);
                            var change_count = providers.length;
                            var failed = response.data.providers_failed;

                            for (var i = 0; i < change_count; i++) {
                                greylistData.commonMailProviders[providers[i]].is_trusted = trust ? true : false;
                            }

                            var results = {};

                            results.failed = failed;

                            if (trust) {
                                results.trusted = providers;
                            } else {
                                results.untrusted = providers;
                            }
                            deferred.resolve(results);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            greylistData.trustCommonMailProviders = function(settings) {
                return greylistData.trustOrUntrustProviders(true, settings);
            };

            greylistData.untrustCommonMailProviders = function(settings) {
                return greylistData.trustOrUntrustProviders(false, settings);
            };

            greylistData.saveCommonMailProviders = function(settings, autotrust) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cpgreylist_save_common_mail_providers_config");

                apiCall.addArgument("autotrust_new_common_mail_providers", autotrust ? 1 : 0);

                for (var provider in settings) {
                    if (settings.hasOwnProperty(provider)) {
                        apiCall.addArgument(provider, settings[provider].autoupdate ? 1 : 0);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var providers = response.data.common_mail_providers;
                            greylistData.autotrust_new_common_mail_providers = PARSE.parsePerlBoolean(response.data.autotrust_new_common_mail_providers);
                            for (var provider in providers) {
                                if (providers[provider].hasOwnProperty("autoupdate")) {
                                    if (!greylistData.commonMailProviders.hasOwnProperty(provider)) {
                                        greylistData.commonMailProviders[provider] = {};
                                        greylistData.commonMailProviders[provider].is_trusted = greylistData.autotrust_new_common_mail_providers;
                                        greylistData.commonMailProviders[provider].display_name = providers[provider].display_name;
                                    }
                                    greylistData.commonMailProviders[provider].autoupdate = PARSE.parsePerlBoolean(providers[provider].autoupdate);
                                }
                            }
                            deferred.resolve(true);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            greylistData.saveConfigSettings = function(config) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "save_cpgreylist_config");
                for (var setting in config) {
                    if (greylistData.configSettings.hasOwnProperty(setting)) {
                        if (setting === "is_enabled" || setting === "is_exim_enabled") {
                            continue;
                        } else if (typeof config[setting] === "boolean") {
                            apiCall.addArgument(setting, config[setting] === true ? 1 : 0);
                        } else {
                            apiCall.addArgument(setting, config[setting]);
                        }
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            for (var returnedSetting in response.data.cpgreylist_config) {
                                if (greylistData.configSettings.hasOwnProperty(returnedSetting)) {
                                    if (returnedSetting === "is_enabled" ||
                                            returnedSetting === "is_exim_enabled" ||
                                            returnedSetting === "spf_bypass") {
                                        greylistData.configSettings[returnedSetting] = PARSE.parsePerlBoolean(response.data.cpgreylist_config[returnedSetting]);
                                    } else {
                                        greylistData.configSettings[returnedSetting] = parseInt(response.data.cpgreylist_config[returnedSetting], 10);
                                    }
                                }
                            }
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            greylistData.status = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cpgreylist_status");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        greylistData.configSettings.is_enabled = PARSE.parsePerlBoolean(response.data.is_enabled);
                        greylistData.configSettings.is_exim_enabled = PARSE.parsePerlBoolean(response.data.is_exim_enabled);
                        deferred.resolve(greylistData.configSettings);
                    });

                return deferred.promise;
            };

            greylistData.enable = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "enable_cpgreylist");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            greylistData.configSettings.is_enabled = true;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            greylistData.disable = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "disable_cpgreylist");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.status);
                            greylistData.configSettings.is_enabled = false;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            greylistData.enabled = function() {
                return greylistData.configSettings.is_enabled;
            };

            greylistData.addTrustedHosts = function(ips_to_add, comment) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "create_cpgreylist_trusted_host");
                apiCall.addArgument("comment", comment);

                for (var a = 0; a < ips_to_add.length; a++) {
                    apiCall.addArgument("ip-" + a, ips_to_add[a]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var ips_added = [],
                                ips_updated = [];

                                // process all the new records
                            for (var l = 0, len = response.data.ips_added.length; l < len; l++) {
                                var ip = response.data.ips_added[l].host_ip;
                                var index = -1;

                                // see if we can find an existing record
                                for (var i = 0, cacheLen = greylistData.trustedHosts.length; i < cacheLen; i++) {
                                    var item = greylistData.trustedHosts[i];
                                    if (item.host_ip === ip) {
                                        index = i;
                                        break;
                                    }
                                }

                                if (index !== -1) {

                                    // update the existing record in our structure
                                    greylistData.trustedHosts[index] = response.data.ips_added[l];
                                    ips_updated.push(ip);
                                } else {

                                    // new record, so add it to the array
                                    greylistData.trustedHosts.push(response.data.ips_added[l]);
                                    ips_added.push(ip);
                                }
                            }

                            deferred.resolve({
                                rejected: response.data.ips_failed,
                                added: ips_added,
                                updated: ips_updated,
                                comment: response.data.comment
                            });

                        } else {

                            var error_details = {
                                main_message: response.error,
                                secondary_messages: []
                            };

                            var ips_rejected = Object.keys(response.data.ips_failed);

                            var ip_to_show_in_message;
                            for (var ed = 0; ed < ips_rejected.length; ed++) {
                                ip_to_show_in_message = _.escape(response.data.ips_failed[ips_rejected[ed]]);
                                error_details.secondary_messages.push(ip_to_show_in_message);
                            }

                            deferred.reject(error_details);
                        }
                    });

                return deferred.promise;
            };

            greylistData.deleteTrustedHosts = function(hostsToDelete) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "delete_cpgreylist_trusted_host");
                var hostCount = hostsToDelete.length;
                for (var i = 0; i < hostCount; i++) {
                    apiCall.addArgument("ip-" + i, hostsToDelete[i]);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            var i = 0,
                                len = response.data.ips_removed.length;

                            var hostsActuallyDeleted = [];

                            for (; i < len; i++) {
                                hostsActuallyDeleted.push(_.find(greylistData.trustedHosts, { host_ip: response.data.ips_removed[i] }));
                            }

                            if (hostsActuallyDeleted.length > 0) {
                                greylistData.trustedHosts = _.difference(greylistData.trustedHosts, hostsActuallyDeleted);
                            }

                            deferred.resolve({
                                removed: response.data.ips_removed,
                                not_removed: response.data.ips_failed
                            });
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });
                return deferred.promise;
            };

            greylistData.deleteAllTrustedHosts = function() {
                var i = 0,
                    len = greylistData.trustedHosts.length,
                    ipsToDelete = [];

                for (; i < len; i++) {
                    ipsToDelete.push(greylistData.trustedHosts[i].host_ip);
                }
                return greylistData.deleteTrustedHosts(ipsToDelete);
            };

            greylistData.loadTrustedHosts = function(forceReload) {
                var deferred = $q.defer();

                if (forceReload) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "read_cpgreylist_trusted_hosts");
                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {
                            response = response.parsedResponse;
                            if (response.status) {

                                // on API call success, populate data structure
                                greylistData.trustedHosts = response.data;

                                deferred.resolve(null);
                            } else {

                                // pass the error along
                                deferred.reject(response.error);
                            }
                        });
                } else {

                    // send a promise with null.
                    // we are already grabbing the current trustedHosts data structure in the controller.
                    deferred.resolve(null);
                }
                return deferred.promise;
            };

            greylistData.isServerNetblockTrusted = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "cpgreylist_is_server_netblock_trusted");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var trustedBlocks = [],
                                untrustedBlocks = [],
                                ip_blocks = response.data.ip_blocks;

                                // process all the blocks
                            var keys = _.keys(ip_blocks);
                            for (var l = 0, len = keys.length; l < len; l++) {
                                var block = keys[l];
                                var isTrusted = PARSE.parsePerlBoolean(ip_blocks[keys[l]]);

                                if (isTrusted) {
                                    trustedBlocks.push(block);
                                } else {
                                    untrustedBlocks.push(block);
                                }
                            }

                            // figure out if all the blocks are trusted
                            var areAllBlocksTrusted;
                            if (untrustedBlocks.length > 0) {
                                areAllBlocksTrusted = false;
                            } else {
                                areAllBlocksTrusted = true;
                            }

                            // return an object that tells us if all the blocks are trusted,
                            // the actual blocks that are not trusted, and the all the blocks
                            deferred.resolve({
                                status: areAllBlocksTrusted,
                                untrusted: untrustedBlocks,
                                netblock: trustedBlocks.concat(untrustedBlocks)
                            });

                        } else {
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };


            greylistData.fetchDeferredEntries = function(meta) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "read_cpgreylist_deferred_entries");
                if (meta) {
                    if (meta.filterBy && meta.filterValue) {
                        apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                    }
                    if (meta.sortBy && meta.sortDirection) {
                        apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                    }
                    if (meta.pageNumber) {
                        apiCall.addPaging(meta.pageNumber, meta.pageSize || 20);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            var return_data = {};

                            return_data.list = response.data.greylist_deferred_entries;
                            return_data.utc_offset = response.data.server_tzoffset;
                            return_data.timezone = response.data.server_timezone;
                            return_data.meta = response.meta;

                            deferred.resolve(return_data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });
                return deferred.promise;
            };

            return greylistData;
        }
        ]);

        return greylistDataSource;
    }
);
