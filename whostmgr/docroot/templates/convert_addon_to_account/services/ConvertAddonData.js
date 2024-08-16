/*
# templates/convert_addon_to_account/services/ConvertAddonData.js Copyright(c) 2020 cPanel, L.L.C.
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

        var convertAddonData = app.factory("ConvertAddonData", ["$q", "defaultInfo", function($q, defaultInfo) {

            var addonData = {};

            addonData.domains = [];
            var default_options = {
                "email-accounts": true,
                "autoresponders": true,
                "email-forwarders": true,
                "docroot": true,
                "preserve-ownership": true,
                "custom-dns-records": true,
                "mysql_dbs": [],
                "mysql_users": [],
                "db_move_type": "move",
                "custom-vhost-includes": true,
                "copy-installed-ssl-cert": true,
                "ftp-accounts": true,
                "webdisk-accounts": true
            };

            function _getAddonData(domain) {
                var data = addonData.domains.filter(function(domain_data) {
                    return domain === domain_data.addon_domain;
                });
                return (data.length) ? data[0] : {};
            }

            /**
             * Fetch the addon domain
             *
             * @method getAddonDomain
             * @param {string} addonDomain - the addon domain you want to get
             * @returns A Promise that resolves to an object for the addon domain
             */
            addonData.getAddonDomain = function(addonDomain) {

                // If the domains data is empty, then we should fetch the data first
                if (addonData.domains.length === 0) {
                    return $q.when(addonData.loadList())
                        .then(function(result) {
                            return _getAddonData(addonDomain);
                        });
                } else {
                    return $q.when(_getAddonData(addonDomain));
                }
            };

            addonData.getAddonDomainDetails = function(addonDomain) {

                // if we already fetched the details previously, shortcircuit this api call
                var found = _getAddonData(addonDomain);
                if (Object.keys(found).length > 1 && Object.keys(found.details).length > 1) {
                    return $q.when(found);
                } else {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "convert_addon_fetch_domain_details");
                    apiCall.addArgument("domain", addonDomain);

                    return $q.when(API.promise(apiCall.getRunArguments()))
                        .then(function(response) {
                            response = response.parsedResponse;

                            // update this addon domain in the data structure
                            // with the details
                            return addonData.getAddonDomain(addonDomain)
                                .then(function(result) {
                                    if (response.data !== null) {
                                        angular.extend(result.details, response.data);

                                        // if the addon domain has no options, initialize it with some
                                        if (Object.keys(result.move_options).length === 0) {
                                            angular.extend(result.move_options, default_options);
                                        }
                                    }

                                    return result;
                                });
                        })
                        .catch(function(response) {
                            response = response.parsedResponse;
                            return response.error;
                        });
                }
            };

            addonData.convertDomainObjectToList = function(domainObject) {
                addonData.domains = Object.keys(domainObject).map(function(domainName) {
                    var domainDetail = domainObject[domainName];
                    domainDetail.addon_domain = domainName;
                    domainDetail.details = {};
                    domainDetail.move_options = {};
                    domainDetail.account_settings = {};
                    return domainDetail;
                });
            };

            addonData.loadList = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_list_addon_domains");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            addonData.convertDomainObjectToList(response.data);
                            deferred.resolve(addonData.domains);
                        } else {

                            // pass the error along
                            deferred.reject(response.error);
                        }
                    });

                // pass the promise back to the controller

                return deferred.promise;
            };

            addonData.beginConversion = function(addon) {
                var i, len;
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "convert_addon_initiate_conversion");

                for (var setting in addon.account_settings) {
                    if (addon.account_settings.hasOwnProperty(setting)) {
                        apiCall.addArgument(setting, addon.account_settings[setting]);
                    }
                }

                for (var service in addon.move_options) {
                    if (addon.move_options.hasOwnProperty(service)) {

                        // ignore this value
                        if (service === "db_move_type") {
                            continue;
                        }

                        if (service === "mysql_dbs") {
                            for (i = 0, len = addon.move_options[service].length; i < len; i++) {
                                if (addon.move_options.db_move_type === "copy") {
                                    apiCall.addArgument("copymysqldb-" + addon.move_options[service][i].name,
                                        addon.move_options[service][i].new_name);
                                } else {
                                    apiCall.addArgument("movemysqldb-" + i, addon.move_options[service][i].name);
                                }
                            }
                        } else if (service === "mysql_users" && addon.move_options.db_move_type === "move") {
                            for (i = 0, len = addon.move_options[service].length; i < len; i++) {
                                apiCall.addArgument("movemysqluser-" + i, addon.move_options[service][i].name);
                            }
                        } else {

                            // The backend expects boolean options to use 1 or 0
                            if (_.isBoolean(addon.move_options[service])) {
                                apiCall.addArgument(service, (addon.move_options[service]) ? 1 : 0);
                            } else {
                                apiCall.addArgument(service, addon.move_options[service]);
                            }
                        }
                    }
                }

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return response.data;
                        } else {
                            return $q.reject(response.meta);
                        }
                    });
            };

            addonData.init = function() {
                addonData.convertDomainObjectToList(defaultInfo.addon_domains);
            };

            addonData.init();

            return addonData;
        }]);

        return convertAddonData;
    }
);
