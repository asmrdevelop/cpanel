/*
# passenger/services/domains.js                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/api2-request",
        "cjt/io/api2",
        "cjt/util/httpStatus",
        "cjt/core",
        "cjt/services/APIService"
    ],
    function(angular, $, _, LOCALE, API, APIREQUEST, APIDRIVER, HTTP_STATUS, CJT) {

        var app = angular.module("cpanel.applicationManager");
        var factory = app.factory(
            "Domains",
            ["$q", "defaultInfo", "APIService", function($q, defaultInfo, APIService) {

                var types = {
                    "addon_domains": LOCALE.maketext("Addon Domains"),
                    "main_domain": LOCALE.maketext("Main Domain"),
                    "sub_domains": LOCALE.maketext("Subdomains")
                };

                function determine_group(type) {
                    if (types[type]) {
                        return types[type];
                    } else {
                        return LOCALE.maketext("Other");
                    }
                }

                function massage_data(data) {
                    var formatted_data = [];

                    for (var j = 0, keys = _.keys(data).sort(), key_len = keys.length; j < key_len; j++) {
                        var category = keys[j];
                        if (category === "cp_php_magic_include_path.conf" || category === "parked_domains") {
                            continue;
                        }

                        if (!_.isArray(data[category])) {
                            formatted_data.push({
                                "domain": data[category],
                                "type": determine_group(category)
                            });
                        } else {
                            var temp_array = [];
                            for (var i = 0, len = data[category].length; i < len; i++) {
                                temp_array.push({
                                    "domain": data[category][i],
                                    "type": determine_group(category)
                                });
                            }
                            formatted_data = formatted_data.concat(_.sortBy(temp_array, ["domain"]));
                        }
                    }

                    return formatted_data;
                }

                var DomainsService = function() {};
                DomainsService.prototype = new APIService();
                DomainsService.domains = [];

                angular.extend(DomainsService.prototype, {
                    fetch: function() {
                        if (this.domains.length === 0) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("DomainInfo", "list_domains");

                            var deferred = this.deferred(apiCall, {
                                transformAPISuccess: function(response) {
                                    this.domains = massage_data(response.data);
                                    return this.domains;
                                }
                            });
                            return deferred.promise;
                        } else {
                            return $q.when(this.domains);
                        }
                    },

                    init: function() {
                        this.domains = massage_data(defaultInfo.domains);
                    }

                });


                var service = new DomainsService();
                service.init();

                return service;
            }]);

        return factory;
    }
);
