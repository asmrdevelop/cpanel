/*
# templates/mod_security/services/vendorService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Normalize the vendor to account for any missing data, type conversion, etc.
         *
         * @method _normalizeVendor
         * @private
         * @param  {Object} vendor Vendor returned from the server.
         * @return {Object}        Vendor with all the fields normalized and patched.
         */
        function _normalizeVendor(vendor) {
            vendor.cpanel_provided = PARSE.parsePerlBoolean(vendor.cpanel_provided);
            vendor.enabled = PARSE.parsePerlBoolean(vendor.enabled);
            vendor.update = PARSE.parsePerlBoolean(vendor.update);
            vendor.installed = PARSE.parsePerlBoolean(vendor.installed);
            vendor.totalEnabled = 0;
            vendor.totalDisabled = 0;

            if (vendor.configs) {
                for (var i = 0, l = vendor.configs.length; i < l; i++) {
                    var config = vendor.configs[i];
                    config.enabled = PARSE.parsePerlBoolean(config.active);
                    delete config.active;
                    if (config.enabled) {
                        vendor.totalEnabled++;
                    } else {
                        vendor.totalDisabled++;
                    }
                }

                // Sort initially by config
                vendor.configs.sort(function(configA, configB) {
                    return configA.config.localeCompare(configB.config);
                });
            }

            return vendor;
        }

        /**
         * Converts the response to our application data structure
         * @method _convertResponseToList
         * @private
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function _convertResponseToList(response) {
            var items = [];

            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var vendor = data[i];

                    // Mark the record as unchanged
                    vendor.changed = false;

                    items.push(
                        _normalizeVendor(vendor)
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
        }

        /**
         * Normalize the outcome for an enable/disable config operation for
         * missing data, type conversion, etc.
         *
         * @method _normalizeOutcome
         * @private
         * @param  {Object} outcome Outcome returned from the server.
         * @param  {Boolean} enableCalled true if we are trying to enable, false otherwise
         * @return {Object}        Outcome with all the fields normalized and patched.
         */
        function _normalizeOutcome(outcome, enableCalled) {
            var ok = PARSE.parsePerlBoolean(outcome.ok);
            outcome.ok = ok;
            outcome.enabled = enableCalled ? ok : !ok;
            return outcome;
        }

        /**
         * Cleans up the response for outcomes
         *
         * @method _convertOutcomeResponseToList
         * @private
         * @param  {Array} outcomes
         * @param  {Boolean} enableCalled true if we are trying to enable, false otherwise
         * @return {Array} Sanitized data structure.
         */
        function _convertOutcomeResponseToList(data, enableCalled) {
            var configs = [];
            var totalEnabled = 0;
            var totalDisabled = 0;

            if (data) {
                for (var i = 0, length = data.length; i < length; i++) {
                    var config = data[i];

                    configs.push(
                        _normalizeOutcome(config, enableCalled)
                    );
                    if (config.enabled) {
                        totalEnabled++;
                    } else {
                        totalDisabled++;
                    }
                }
            }

            return {
                configs: configs,
                totalEnabled: totalEnabled,
                totalDisabled: totalDisabled
            };
        }

        /**
         * Returns a promise with vendor information that optionally adds the vendor to the list
         *
         * @method _returnVendor
         * @private
         * @param  {Deferred} deferred
         * @param  {String} method      The API method to call.
         * @param  {Object} parameters  Parameters for the add and preview methods
         *   @param  {String} url       Vendor URL for the YAML file describing the vendor configuration.
         * @return {Promise}
         */
        var _returnVendor = function(deferred, method, parameters) {
            var apiCall = new APIREQUEST.Class();
            apiCall.initialize(NO_MODULE, method);
            apiCall.addArgument("url", parameters.url);

            this.deferred(apiCall, {
                transformAPISuccess: function(response) {
                    return response.data;
                }
            }, deferred);

            // pass the promise back to the controller
            return deferred.promise;
        };

        /**
         * Setup the configuration models API service
         */
        app.factory("vendorService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var VendorService = function() {};
            VendorService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(VendorService.prototype, {

                /**
                 * Get a single vendor by its id from the backend.
                 *
                 * @method fetchVendorById
                 * @param {number} vendorId Id of the vendor to fetch.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchVendorById: function(vendorId) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_vendors");
                    apiCall.addArgument("show_uninstalled", 1);
                    apiCall.addFilter("vendor_id", "eq", vendorId);

                    var deferred = this.deferred(apiCall, {
                        apiSuccess: function(response, deferred) {
                            var results = _convertResponseToList(response);
                            if (results.items.length === 1) {
                                deferred.resolve(results.items[0]);
                            } else if (results.items.length > 1) {
                                deferred.reject(LOCALE.maketext("You have multiple vendors with the same [asis,vendor_id]."));
                            } else {
                                deferred.reject(LOCALE.maketext("The system could not find the specified [asis,vendor_id].", vendorId));
                            }
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get a list of vendors
                 * * @param {object} meta Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy Name of the field to sort by
                 *   @param {string} meta.sordDirection asc or desc
                 *   @param {string} meta.sortType Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy Name of the field to filter by
                 *   @param {string} meta.filterCompare Optional comparator to use when comparing for filter.
                 *   @param {string} meta.filterValue  Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber Page number to fetch.
                 *   @param {string} meta.pageSize Size of a page, will default to 10 if not provided.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function(meta) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_vendors");
                    apiCall.addArgument("show_uninstalled", 1);
                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.pageNumber) {
                            apiCall.addPaging(meta.pageNumber, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    return this.deferred(apiCall, {
                        transformAPISuccess: _convertResponseToList
                    }).promise;
                },

                /**
                 * Disable a vendor by id
                 *
                 * @method disableVendor
                 * @param  {Number}  id     Vendor id.
                 * @return {Promise}
                 */
                disableVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor");
                    apiCall.addArgument("vendor_id", id);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable a vendor by id
                 *
                 * @method enableRule
                 * @param  {Number} id  Vendor id.
                 * @return {Promise}
                 */
                enableVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor");
                    apiCall.addArgument("vendor_id", id);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Disable a config file by path
                 *
                 * @method disableConfig
                 * @param  {String}  config     Path to the specific config file.
                 * @return {Promise}
                 */
                disableConfig: function(config) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_make_config_inactive");
                    apiCall.addArgument("config", config);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable a config file by path
                 *
                 * @method disableConfig
                 * @param  {String}  config     Path to the specific config file.
                 * @return {Promise}
                 */
                enableConfig: function(config) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_make_config_active");
                    apiCall.addArgument("config", config);

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Enable all the config files for a vendor
                 *
                 * @method enableAllConfigs
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                enableAllConfigs: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor_configs");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: function(response) {
                            return _convertOutcomeResponseToList(response.data, true);
                        },
                        transformAPIFailure: function(response) {
                            return _convertOutcomeResponseToList(response.data, true);
                        }
                    });

                    return deferred.promise;
                },

                /**
                 * Disable all the config files for a vendor
                 *
                 * @method disableAllConfigs
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                disableAllConfigs: function(id) {

                    // make a promise
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor_configs");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall, {
                        transformAPISuccess: function(response) {
                            return _convertOutcomeResponseToList(response.data, false);
                        },
                        transformAPIFailure: function(response) {
                            return _convertOutcomeResponseToList(response.data, false);
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Enable automatic updates for a vendor
                 *
                 * @method enableVendorUpdates
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                enableVendorUpdates: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_enable_vendor_updates");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Disable automatic updates for a vendor
                 *
                 * @method disableVendorUpdates
                 * @param  {String}  id     Vendor id.
                 * @return {Promise}
                 */
                disableVendorUpdates: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_disable_vendor_updates");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Remove a vendor from the system by its id
                 *
                 * @method deleteVendor
                 * @param  {Number} id Vendor id for the vendor to delete.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                deleteVendor: function(id) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_remove_vendor");
                    apiCall.addArgument("vendor_id", id);

                    var deferred = this.deferred(apiCall);
                    return deferred.promise;
                },

                /**
                 * Retrieves vendor information from a remote URL containing configuration information
                 * stored in a YAML format.
                 *
                 * @method loadVendor
                 * @param  {String} url Vendor URL for the YAML file describing the vendor configuration.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                loadVendor: function(url) {

                    // make a promise
                    var deferred = $q.defer(),
                        parameters = {
                            url: url
                        };

                    // pass the promise back to the controller
                    return _returnVendor.call(this, deferred, "modsec_preview_vendor", parameters);
                },

                /**
                 * Adds a vendor configuration to the list of vendors
                 *
                 * @method saveVendor
                 * @param  {String} url         Vendor URL for the YAML file describing the vendor configuration.
                 * @return {Promise}            Promise that will fulfill the request.
                 */
                saveVendor: function(url) {

                    // make a promise
                    var deferred = $q.defer(),
                        parameters = {
                            url: url,
                        };

                    // pass the promise back to the controller
                    return _returnVendor.call(this, deferred, "modsec_add_vendor", parameters);
                },

                /**
                * Helper method that calls _convertResponseToList to prepare the data structure
                *
                * @method prepareList
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return _convertResponseToList(response);
                }
            });

            return new VendorService();
        }]);
    }
);
