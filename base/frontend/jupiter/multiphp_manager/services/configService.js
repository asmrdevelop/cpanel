/*
 * multiphp_manager/services/configService.js        Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/uapi-request",
        "cjt/io/uapi", // IMPORTANT: Load the driver so its ready
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST, APIDRIVER) {
        "use strict";

        var app = angular.module("cpanel.multiPhpManager.service", ["cjt2.services.api"]);

        /**
         * Setup the account list model's API service
         */
        app.factory("configService", ["$q", "APIService", function($q, APIService) {

            // return the factory interface
            return {

                /**
                 * Converts the response to our application data structure
                 * @param  {Object} response
                 * @return {Object} Sanitized data structure.
                 */
                convertResponseToList: function(response) {
                    var items = [];
                    if (response.status) {
                        var data = response.data;
                        for (var i = 0, length = data.length; i < length; i++) {
                            var list = data[i];

                            // add PHP user friendly version format
                            if (list.version) {
                                list.displayPhpVersion = this.transformPhpFormat(list.version);
                            }

                            items.push(
                                list
                            );
                        }

                        var meta = response.meta;

                        var totalItems = meta.paginate.total_records || data.length;
                        var totalPages = meta.paginate.total_pages || 1;

                        return {
                            items: items,
                            totalItems: totalItems,
                            totalPages: totalPages
                        };
                    } else {
                        return {
                            items: [],
                            totalItems: 0,
                            totalPages: 0
                        };
                    }
                },

                /**
                 * Set a given PHP version to the given list of vhosts.
                 * version: PHP version to apply to the provided vhost list.
                 * vhostList: List of vhosts to which the new PHP needs to be applied.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                applyDomainSetting: function(version, vhostList) {

                    // make a promise
                    var deferred = $q.defer();
                    var that = this;
                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("LangPHP", "php_set_vhost_versions");
                    apiCall.addArgument("version", version);

                    if (typeof (vhostList) !== "undefined" && vhostList.length > 0) {
                        vhostList.forEach(function(vhost, index) {
                            apiCall.addArgument("vhost-" + index, vhost);
                        });
                    }

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {

                                // Keep the promise
                                deferred.resolve(response.data);
                            } else {

                                // Pass the error along
                                deferred.reject(response);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get a list of accounts along with their default PHP versions for the given search/filter/page criteria.
                 * @param {object} meta - Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy - Name of the field to sort by
                 *   @param {string} meta.sortDirection - asc or desc
                 *   @param {string} meta.sortType - Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy - Name of the field to filter by
                 *   @param {string} meta.filterValue - Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber - Page number to fetch.
                 *   @param {string} meta.pageSize - Size of a page, will default to 10 if not provided.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchList: function(meta) {

                    // make a promise
                    var deferred = $q.defer();
                    var that = this;
                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("LangPHP", "php_get_vhost_versions");
                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.currentPage) {
                            apiCall.addPaging(meta.currentPage, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterCompare && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = that.convertResponseToList(response);

                                // Keep the promise
                                deferred.resolve(results);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get a list of domains that are inherit PHP version from a given location.
                 * @param {string} location - The location for which PHP version is changed.
                 *   example: domain:foo.tld, system:default
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchImpactedDomains: function(type, value) {
                    var apiCall = new APIREQUEST.Class();
                    var apiService = new APIService();

                    apiCall.initialize("LangPHP", "php_get_impacted_domains");
                    apiCall.addArgument(type, value);

                    var deferred = apiService.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Convert PHP package name (eg: ea-php56)
                 * to a user friendly string (eg: PHP 5.6)
                 * @param  {String}
                 * @return {String}
                 */
                friendlyPhpFormat: function(str) {
                    var newStr = str || "";
                    var phpVersionRegex = /^\D+-(php)(\d{2,3})$/i;
                    if (phpVersionRegex.test(str)) {
                        var stringArr = str.match(phpVersionRegex);

                        // adds a period before the last digit
                        var formattedNumber = stringArr[2].replace(/(\d)$/, ".$1");

                        newStr = "PHP " + formattedNumber;
                    }
                    return newStr;
                },

                /**
                 * Format PHP package name (eg: ea-php99)
                 * to a display format (eg: PHP 5.6 (ea-php99))
                 * @param  {String}
                 * @return {String}
                 */
                transformPhpFormat: function(str) {
                    str = str || "";
                    var newStr = this.friendlyPhpFormat(str);
                    return (newStr !== "" && newStr !== str) ? newStr + " (" + str + ")" : str;
                },

                /**
                 * Gets recommendation data for EasyApache 4.
                 * @method getEA4Recommendations
                 * @return {Promise}
                 */
                getEA4Recommendations: function() {
                    var apiCall = new APIREQUEST.Class();
                    var apiService = new APIService();
                    apiCall.initialize("EA4", "get_recommendations");
                    var deferred = apiService.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Gets custom php recommendations. These can be defined in the file
                 * '/etc/cpanel/ea4/recommendations/custom_php_recommendation.json'.
                 * @method getCustomRecommendations
                 * @return {Promise}
                 */
                getCustomRecommendations: function() {
                    var apiCall = new APIREQUEST.Class();
                    var apiService = new APIService();
                    apiCall.initialize("EA4", "get_php_recommendations");
                    var deferred = apiService.deferred(apiCall);
                    return deferred.promise;
                }
            };
        }]);
    }
);
