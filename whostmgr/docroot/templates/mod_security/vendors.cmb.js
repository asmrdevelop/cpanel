/*
# templates/mod_security/views/commonController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/* ------------------------------------------------------------------------------
* DEVELOPER NOTES:
*  1) Put all common application functionality here, maybe
*-----------------------------------------------------------------------------*/

define(
    'app/views/commonController',[
        "angular",
        "cjt/filters/wrapFilter",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "uiBootstrap"
    ],
    function(angular) {

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", ["ui.bootstrap", "ngSanitize"]);
        }

        var controller = app.controller(
            "commonController",
            ["$scope", "$location", "$rootScope", "alertService", "PAGE",
                function($scope, $location, $rootScope, alertService, PAGE) {

                // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Bind the alerts service to the local scope
                    $scope.alerts = alertService.getAlerts();

                    $scope.route = null;

                    /**
                 * Closes an alert and removes it from the alerts service
                 *
                 * @method closeAlert
                 * @param {String} index The array index of the alert to remove
                 */
                    $scope.closeAlert = function(id) {
                        alertService.remove(id);
                    };

                    /**
                 * Determines if the current view matches the supplied pattern
                 *
                 * @method isCurrentView
                 * @param {String} view The path to the view to match
                 */
                    $scope.isCurrentView = function(view) {
                        if ( $scope.route && $scope.route.$$route ) {
                            return $scope.route.$$route.originalPath === view;
                        }
                        return false;
                    };

                    // register listener to watch route changes
                    $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        $scope.route = next;
                    });
                }
            ]);


        return controller;
    }
);

/*
# templates/mod_security/services/vendorService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/vendorService',[

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

/*
# templates/mod_security/views/vendorListController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/vendorListController',[
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "cjt/io/whm-v1-querystring-service"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "vendorListController", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$routeParams",
                "$timeout",
                "vendorService",
                "alertService",
                "spinnerAPI",
                "queryService",
                "PAGE",
                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $routeParams,
                    $timeout,
                    vendorService,
                    alertService,
                    spinnerAPI,
                    queryService,
                    PAGE) {

                    /**
                         * Load the edit vendor view with the  requested vendor.
                         *
                         * @method loadEditVendorView
                         * @param  {Object} vendor
                         * @param  {Boolean} force if true, will show the special warning.
                         */
                    $scope.loadEditVendorView = function(vendor, force) {
                        var args = { id: vendor.vendor_id };
                        if (typeof (force) !== "undefined" && force === true) {
                            args["force"] = true.toString();
                        }
                        $scope.loadView("vendors/edit", args);
                    };

                    /**
                         * Clear the search query
                         *
                         * @method clearFilter
                         * @return {Promise}
                         */
                    $scope.clearFilter = function() {
                        $scope.meta.filterValue = "";
                        $scope.activeSearch = false;
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        queryService.query.clearSearch();

                        // select the first page of search results
                        return $scope.selectPage(1);
                    };

                    /**
                         * Start a search query
                         *
                         * @method startFilter
                         * @return {Promise}
                         */
                    $scope.startFilter = function() {
                        $scope.activeSearch = true;
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        queryService.query.clearSearch();
                        queryService.query.addSearchField("*", "contains", $scope.meta.filterValue);

                        return $scope.selectPage(1)
                            .then(function() {
                                $scope.filteredData = true;
                            });
                    };

                    /**
                         * Select a specific page of vendors
                         *
                         * @method selectPage
                         * @param  {Number} [page] Optional page number, if not provided will use the current
                         * page provided by the scope.meta.pageNumber.
                         * @return {Promise}
                         */
                    $scope.selectPage = function(page) {

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.pageNumber = page;
                        }

                        // Leave history so refresh works
                        queryService.query.updatePagination($scope.meta.pageNumber, $scope.meta.pageSize);

                        return $scope.fetch();
                    };

                    /**
                         * Sort the list of rules
                         *
                         * @param {Object}  meta         The sort model.
                         * @param {Boolean} defaultSort  If true, the sort was not not initiated by the user
                         */
                    $scope.sortList = function(meta, defaultSort) {
                        queryService.query.clearSort();
                        queryService.query.addSortField(meta.sortBy, meta.sortType, meta.sortDirection);

                        if (!defaultSort) {
                            $scope.fetch();
                        }
                    };

                    /**
                         * Handles the keybinding for the clearing and searching.
                         * Esc clears the search field.
                         * Enter performs a search.
                         *
                         * @method triggerToggleSearch
                         * @param {Event} event - The event object
                         */
                    $scope.triggerToggleSearch = function(event) {

                        // clear on Esc
                        if (event.keyCode === 27) {
                            $scope.toggleSearch(true);
                        }

                        // filter on Enter
                        if (event.keyCode === 13) {
                            $scope.toggleSearch();
                        }
                    };

                    /**
                         * Toggles the clear button and conditionally performs a search.
                         * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                         *
                         * @method toggleSearch
                         * @param {Boolean} isClick Toggle button clicked.
                         * @return {Promise}
                         */
                    $scope.toggleSearch = function(isClick) {
                        var filter = $scope.meta.filterValue;

                        if ( !filter && ($scope.activeSearch  || $scope.filteredData)) {

                            // no query in box, but we prevously filtered or there is an active search
                            return $scope.clearFilter();
                        } else if (isClick && $scope.activeSearch ) {

                            // User clicks clear
                            return $scope.clearFilter();
                        } else if (filter) {
                            return $scope.startFilter();
                        }
                    };

                    /**
                         * Fetch the list of hits from the server
                         *
                         * @method fetch
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.fetch = function() {
                        spinnerAPI.start("loadingSpinner");
                        return vendorService
                            .fetchList($scope.meta)
                            .then(function(results) {
                                $scope.vendors = results.items;
                                $scope.totalItems = results.totalItems;
                                $scope.totalPages = results.totalPages;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetch"
                                });
                            })
                            .then(function() {
                                $scope.loading = false;
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    /**
                         * Set status of a specific vendor.
                         *
                         * @method setVenderStatus
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor status being saved.
                         */
                    $scope.setVenderStatus = function(vendor) {
                        spinnerAPI.start("loadingSpinner");
                        if ( vendor.enabled ) {
                            return vendorService
                                .enableVendor(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.enabled = true;

                                    if (vendor.in_use === 0) {
                                        $scope.loadEditVendorView(vendor, true);
                                    } else {

                                        // success
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("You have successfully enabled the vendor: [_1]", vendor.name),
                                            id: "enableSuccess"
                                        });
                                    }
                                }, function(error) {

                                    // failure
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "enableFailed"
                                    });
                                    vendor.enabled = false;
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        } else {
                            return vendorService
                                .disableVendor(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.enabled = false;

                                    // success
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully disabled the vendor: [_1]", vendor.name),
                                        id: "disableSuccess"
                                    });
                                }, function(error) {

                                    // failure
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "disableFailed"
                                    });
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        }
                    };

                    /**
                         * Sets automatic updates for a vendor.
                         *
                         * @method setVenderUpdate
                         * @param  {Object} vendor
                         * @return {Promise} Promise that, when fulfilled, will result in the update status of a vender being saved.
                         */
                    $scope.setVenderUpdate = function(vendor) {
                        spinnerAPI.start("loadingSpinner");
                        if ( vendor.update ) {
                            return vendorService
                                .enableVendorUpdates(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.update = true;
                                    alertService.add( {
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully enabled automatic updates for the vendor: [_1]", vendor.name),
                                        id: "enableUpdatesSuccess"
                                    } );
                                }, function(error) {
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "enableUpdatesFailed"
                                    } );
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        } else {
                            return vendorService
                                .disableVendorUpdates(vendor.vendor_id)
                                .then(function(result) {
                                    vendor.update = false;
                                    alertService.add( {
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully disabled automatic updates for the vendor: [_1]", vendor.name),
                                        id: "disableUpdatesSuccess"
                                    } );
                                }, function(error) {
                                    alertService.add( {
                                        type: "danger",
                                        message: error,
                                        id: "disableUpdatesFailed"
                                    } );
                                })
                                .then(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                });
                        }
                    };

                    /**
                         * Install the vendor on your system.
                         *
                         * @method install
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor being installed on your system.
                         */
                    $scope.install = function(vendor) {
                        vendor.installing = true;
                        return vendorService
                            .saveVendor(vendor.installed_from)
                            .then(function() {
                                vendor.installed = true;

                                // Report success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully installed the vendor: [_1]", vendor.name),
                                    id: "installSuccess"
                                });

                                spinnerAPI.stop("loadingSpinner");

                                return $scope.fetch();
                            }, function(error) {

                                // failure
                                alertService.add( {
                                    type: "danger",
                                    message: LOCALE.maketext("The system experienced the following error when it attempted to install the “[_1]” vendor: [_2]", vendor.name, error),
                                    id: "installFailed"
                                });

                                throw error;
                            }).finally(function() {

                                // remove the process flag even if the process failed
                                delete vendor.installing;
                            });
                    };

                    /**
                         * Remove the vendor from your system.
                         *
                         * @method delete
                         * @param  {Object} vendor
                         * @return {Promise} Promise that when fulfilled will result in the vendor being removed from your system.
                         */
                    $scope.delete = function(vendor) {
                        vendor.deleting = true;
                        return vendorService
                            .deleteVendor(vendor.vendor_id)
                            .then(function() {

                                // Report success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully removed the vendor: [_1]", vendor.name),
                                    id: "deleteSuccess"
                                });

                                return $scope.fetch();
                            }, function(error) {

                                // We are done deleting so remove
                                // the signaling flag.
                                delete vendor.deleting;

                                // failure
                                alertService.add( {
                                    type: "danger",
                                    message: LOCALE.maketext("The system experienced the following error when it attempted to remove the vendor [_1]: [_2]", vendor.name, error),
                                    id: "deleteFailed"
                                });

                                throw error;
                            });
                    };

                    /**
                         * Test if the current vendor is being deleted.
                         *
                         * @method isDeleting
                         * @param  {Ojbect}  vendor
                         * @return {Boolean}        true if the current vendor being deleted, false otherwise.
                         */
                    $scope.isDeleting = function(vendor) {
                        return vendor.deleting;
                    };

                    /**
                         * Show the delete confirm dialog for the vendor. Will close any other open confirms first.
                         *
                         * @method showDeleteConfirm
                         * @param  {Object} vendor
                         */
                    $scope.showDeleteConfirm = function(vendor) {
                        if (vendor.is_pkg) {
                            window.location.assign("../../scripts7/EasyApache4/review?uninstall=" + vendor.is_pkg);
                            return true;
                        }

                        if ($scope.lastConfirm) {

                            // Close the last one
                            delete $scope.lastConfirm.deleteConfirm;
                            delete $scope.lastConfirm.installConfirm;
                        }
                        vendor.deleteConfirm = true;
                        $scope.lastConfirm = vendor;
                    };

                    /**
                         * Hide the delete confirm dialog for the vendor
                         *
                         * @method hideDeleteConfirm
                         * @param  {Object} vendor
                         */
                    $scope.hideDeleteConfirm = function(vendor) {
                        delete vendor.deleteConfirm;
                    };

                    /**
                         * Test if the delete confirm dialog for a vendor should be shown.
                         *
                         * @method canShowDeleteConfirm
                         * @param  {Object} vendor
                         * @return {Boolean} true if the current vendor should show the confirmation, false otherwise.
                         */
                    $scope.canShowDeleteConfirm = function(vendor) {

                        // cast the value since it can be undefined
                        return !!vendor.deleteConfirm;
                    };

                    /**
                         * Test whether the vendor is installed.
                         *
                         * @method isVendorInstalled
                         * @param  {Object} vendor
                         * @return {Booelan} true if the vendor is installed, false otherwise.
                         */
                    $scope.isVendorInstalled = function(vendor) {
                        return vendor.installed;
                    };

                    /**
                         * Test if the current vendor is being installed.
                         * dialog.
                         *
                         * @method isInstalling
                         * @param  {Ojbect} vendor
                         * @return {Boolean} true if the current vendor being installed, false otherwise.
                         */
                    $scope.isInstalling = function(vendor) {
                        return vendor.installing;
                    };

                    /**
                         * Show the install confirm dialog for the vendor. Will close any other open confirms first.
                         *
                         * @method showInstallConfirm
                         * @param  {Object} vendor
                         */
                    $scope.showInstallConfirm = function(vendor) {
                        if ($scope.lastConfirm) {

                            // Close the last one
                            delete $scope.lastConfirm.deleteConfirm;
                            delete $scope.lastConfirm.installConfirm;
                        }
                        vendor.installConfirm = true;
                        $scope.lastConfirm = vendor;
                    };

                    /**
                         * Hide the install confirm dialog for the vendor
                         *
                         * @method hideInstallConfirm
                         * @param  {Object} vendor
                         */
                    $scope.hideInstallConfirm = function(vendor) {
                        delete vendor.installConfirm;
                    };

                    /**
                         * Test if the install confirm dialog for a vendor should be shown.
                         *
                         * @method canShowInstallConfirm
                         * @param  {Object} vendor
                         * @return {Boolean} true if the current vendor should show the confirmation, false otherwise.
                         */
                    $scope.canShowInstallConfirm = function(vendor) {

                        // cast the value since it can be undefined
                        return !!vendor.installConfirm;
                    };

                    /**
                         * Test if the row dialog for a vendor should be shown.
                         *
                         * @method shouldShowDialog
                         * @param  {Object} vendor
                         * @return {Boolean} true if the vendor is being deleted or is not installed, false otherwise.
                         */
                    $scope.shouldShowDialog = function(vendor) {
                        return $scope.canShowDeleteConfirm(vendor) || $scope.canShowInstallConfirm(vendor);
                    };

                    // setup data structures for the view
                    $scope.loading = true;

                    // Items accounting
                    $scope.vendors = [];
                    $scope.totalPages = 0;
                    $scope.totalItems = 0;

                    // Filter related flags
                    $scope.activeSearch = false;
                    $scope.filteredData = false;
                    $scope.lastConfirm = null;

                    // Meta-data for lister filter, sort and pagination
                    var hasPaging = queryService.route.hasPaging();
                    var pageSize = queryService.DEFAULT_PAGE_SIZE;
                    var page = 1;
                    if (hasPaging) {
                        pageSize = queryService.route.getPageSize();
                        page = queryService.route.getPage();
                    }

                    var sorting = queryService.route.getSortProperties("enabled", "", "asc");
                    var hasFilter = queryService.route.hasSearch();
                    var filterRules = queryService.route.getSearch();

                    $scope.meta = {
                        filterBy: hasFilter ? filterRules[0].field : "*",
                        filterCompare: hasFilter ? filterRules[0].type : "contains",
                        filterValue: hasFilter ? filterRules[0].value : "",
                        pageSize: hasPaging ?  pageSize : queryService.DEFAULT_PAGE_SIZE,
                        pageNumber: hasPaging ? page : 1,
                        sortDirection: sorting.direction,
                        sortBy: sorting.field,
                        sortType: sorting.type,
                        pageSizes: queryService.DEFAULT_PAGE_SIZES
                    };

                    // if the user types something else in the search box, we change the button icon so they can search again.
                    $scope.$watch("meta.filterValue", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.activeSearch = false;
                    });

                    // watch the page size and and load the first page if it changes
                    $scope.$watch("meta.pageSize", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.selectPage(1);
                    });

                    // Determine if we have an active search on load
                    $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Expose any backend exceptions
                    $scope.exception = queryService.prefetch.failed(PAGE.vendors) ? queryService.prefetch.getMetaMessage(PAGE.vendors) : "";

                    // check for page data in the template if this is a first load
                    if (app.firstLoad.vendors && PAGE.vendors) {
                        app.firstLoad.vendors = false;
                        $scope.loading = false;
                        var results = vendorService.prepareList(PAGE.vendors);
                        $scope.vendors = results.items;
                        $scope.totalItems = results.totalItems;
                        $scope.totalPages = results.totalPages;
                    } else {

                        // Otherwise, retrieve it via ajax
                        $timeout(function() {

                            // NOTE: Without this delay the spinners are not created on inter-view navigation.
                            $scope.selectPage(1);
                        });
                    }
                }
            ]
        );

        return controller;
    }
);

/*
# ruleVendorUrlValidator.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

/**
 * This module has validators for the rule vendor url format.
 *
 * @module ruleVendorUrlValidator
 * @requires angular, validator-utils, validate, locale
 */

define('app/directives/ruleVendorUrlValidator',[
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/domain-validators",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, UTILS, LOCALE, DOMAIN_VALIDATORS) {

    /**
         * Expand the protocol with the colon.
         *
         * @private
         * @method _expandProtocol
         * @param  {String} value
         * @return {String}
         */
    var _expandProtocol = function(value) {
        return value + ":";
    };

    var VALID_PROTOCOLS = [ "http", "https" ];
    var VALID_PROTOCOLS_PATTERN = new RegExp("^(?:" + _.map(VALID_PROTOCOLS, _expandProtocol).join("|") + ")$", "i");
    var VALID_FILE_NAME_PATTERN = /^meta_[a-zA-Z0-9_-]+\.yaml$/;
    var VALID_FILE_PREFIX = /^meta_/;
    var VALID_FILE_EXTENSION = /\.yaml$/;

    var validators = {

        /**
             * Checks if the string is valid vendor url. To be valid, it must meet the following rules:
             *   1) It must be a valid url
             *   2) It must only use the http protocol.
             *   3) It must point to a file name with the following parts:
             *       a) Starts with meta_
             *       b) Followed by a vendor name
             *       c) With a .yaml extension.
             *
             * Obviously it must conform to other requirements such as pointing to a valid YAML file in the
             * correct format for a vendor meta data file. These final aspects are validated on the server
             * during load process, not on the client.
             * @param  {String}  value
             * @return {Object}       Returns the extended validation object to the validator.
             */
        isModsecVendorUrl: function(value) {
            var result = UTILS.initializeValidationResult();

            if (value) {

                var parts = value.split(/\//);
                var length = parts.length;
                var last = length - 1;

                // 0) Must have at least 3 forward slashes, indicating that the URL has a protocol, domain and filename
                if (length < 4) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The URL must contain a protocol, domain, and file name in the correct format. (Example: [asis,https://example.com/example/meta_example.yaml])"));
                    return result;
                }

                // 1) Part 0 should be a protocol: http:
                if (!VALID_PROTOCOLS_PATTERN.test(parts[0])) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The URL must use one of the following recognized protocols: [join,~, ,_1]", VALID_PROTOCOLS));
                    return result;
                }

                // 2) Part 1 should be empty from between the //
                //    Note: This test doesn't account for the colon directly, but the error message mentions it because it provides an easy spatial reference
                //    for the user. If we reach this test, we will have passed the protocol test and that one already includes testing for the colon.
                if (parts[1] !== "") {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", LOCALE.maketext("The protocol should be followed by a colon and two forward slashes. (Example: [asis,https://])"));
                    return result;
                }

                // 3) Part 2 should be a domain
                var domainResults = DOMAIN_VALIDATORS.methods.fqdn(parts[2]);
                if (!domainResults.isValid) {
                    result.isValid = false;
                    result.add("isModsecVendorUrl", domainResults.messages[0].message);
                    return result;
                }

                // 4) An optional path, we are just going to ignore it.

                // 5) Part n should be a file name and is not required
                if (last < 3) {
                    result.add("isModsecVendorUrl", LOCALE.maketext("The file name must start with meta_, followed by the vendor name and have the .yaml extension. (Example: [asis,meta_example.yaml])"));
                } else {
                    var fileName = parts[last];

                    if (!VALID_FILE_NAME_PATTERN.test(fileName)) {
                        result.isValid = false;
                        var failedPrefixTest = !VALID_FILE_PREFIX.test(fileName);
                        var failedExtensionTest = !VALID_FILE_EXTENSION.test(fileName);

                        var numFailed = failedPrefixTest + failedExtensionTest; // Implicit coersion to a number

                        // If several conditions fail, give them the whole spiel, otherwise just give them their specific error.
                        if (numFailed > 1) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must use the meta_ prefix, followed by the vendor name and a .yaml extension. The vendor name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])", ["a-z", "A-Z", "0-9", "-", "_"]));
                        } else if (failedPrefixTest) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must use the meta_ prefix. (Example: [asis,meta_example.yaml])"));
                        } else if (failedExtensionTest) {
                            result.add("isModsecVendorUrl", LOCALE.maketext("The file name must have the .yaml extension. (Example: [asis,meta_example.yaml])"));
                        } else { // By the process of elimination, the only part left of the filename that could be wrong is the vendor_id
                            result.add("isModsecVendorUrl", LOCALE.maketext("The vendor name part of the file name must only contain characters in the following set: [join,~, ,_1] (Example: [asis,meta_example.yaml])", ["a-z", "A-Z", "0-9", "-", "_"] ));
                        }

                        return result;
                    }
                }
            }
            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "ruleVendorUrlValidator",
        description: "Validation directives for rule vendor urls.",
        version: 11.48,
    };
});

/*
# templates/mod_security/views/addVendorController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/addVendorController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "app/directives/ruleVendorUrlValidator",
        "cjt/filters/notApplicableFilter",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addVendorController", [
                "$scope",
                "$filter",
                "spinnerAPI",
                "alertService",
                "vendorService",
                function(
                    $scope,
                    $filter,
                    spinnerAPI,
                    alertService,
                    vendorService) {

                    /**
                         * Disable buttons based on form state
                         *
                         * @method disableForm
                         * @param  {FormController} form
                         * @return {Boolean}
                         */
                    $scope.disableForm = function(form) {
                        return form.$pristine || (form.$dirty && form.$invalid) || $scope.loading;
                    };

                    /**
                         * Load the form with vendor configuration from a specified URL
                         *
                         * @method load
                         * @param  {String} url Address of the YAML configuration file
                         * @return {Promise}
                         */
                    $scope.load = function(url) {
                        alertService.clear();
                        spinnerAPI.start("loadingSpinner");
                        $scope.loading = true;
                        return vendorService
                            .loadVendor(url)
                            .then(function(vendor) {
                                angular.extend($scope.vendor, vendor);
                                $scope.vendor.isLoaded = true;
                                $scope.vendor.report_url = $filter("na")($scope.vendor.report_url);
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorLoadVendorConfig",
                                });
                                $scope.vendor.isLoaded = false;
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                                $scope.loading = false;
                            });
                    };

                    /**
                         * Save the form
                         *
                         * @method save
                         * @param  {String} url         Address of the YAML configuration file
                         * @return {Promise}
                         */
                    $scope.save = function(url) {
                        alertService.clear();
                        spinnerAPI.start("savingSpinner");
                        return vendorService
                            .saveVendor(url)
                            .then(function(vendor) {

                                // success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully added “[_1]” to the vendor configuration list.", vendor.name),
                                    id: "successSaveVendorConfig",
                                });
                                $scope.loadView("/vendors");
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorSaveVendorConfig",
                                });
                                $scope.scrollTo("top");
                            })
                            .finally(function() {
                                spinnerAPI.stop("savingSpinner");
                            });
                    };

                    /**
                         * Navigate to the previous view.
                         *
                         * @method  cancel
                         */
                    $scope.cancel = function() {
                        alertService.clear();
                        $scope.loadView("vendors");
                    };

                    /**
                         * Clear alerts and restore form defaults
                         *
                         * @method clearForm
                         */
                    $scope.clearForm = function() {
                        $scope.vendor = {
                            enabled: true,
                            isLoaded: false,
                        };
                        alertService.clear();
                    };

                    // Use SSL for YAML URL recommendation warning

                    $scope.showSSLwarning = false;

                    $scope.vendorURLchange = function(url) {
                        var show = false;
                        var matches = /^(https?):\/\//.exec(url);
                        if (matches && ( matches[1] === "http" ) ) {
                            show = true;
                        }
                        $scope.showSSLwarning = show;
                    };

                    // Initialize the form on first load.
                    $scope.isEditor = false;
                    $scope.clearForm();
                },
            ]
        );

        return controller;
    }
);

/*
# mod_security/views/enableDisableConfigController.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/enableDisableConfigController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/spinnerDirective",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/filters/breakFilter",
        "cjt/filters/replaceFilter",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationItemDirective",
        "cjt/services/alertService",
        "app/services/vendorService"
    ],
    function(angular, _, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("enableDisableConfigController", [
            "$scope",
            "$q",
            "$location",
            "$timeout",
            "vendorService",
            "alertService",
            "spinnerAPI",
            function(
                $scope,
                $q,
                $location,
                $timeout,
                vendorService,
                alertService,
                spinnerAPI) {

                /**
                 * Initialize the view
                 *
                 * @private
                 * @method _initializeView
                 */
                var _initializeView = function() {
                    $scope.filter = "";
                    $scope.filterExpression = null;
                    $scope.hasIssues = false;
                    $scope.meta = {
                        sortBy: "config",
                        sortDirection: "asc"
                    };

                    _clearIssues();

                    $scope.configs = [];
                };

                /**
                 * Load the view data
                 *
                 * @private
                 * @method _loadVendor
                 */
                var _loadVendor = function() {

                    // This control is designed to be used both independently and
                    // embedded in another controller.
                    if (!$scope.vendor) {
                        _loadVendorFromServer();
                    } else if (!$scope.vendor.configs) {
                        _loadVendorFromParent();
                    }
                };

                /**
                 * Load the force flag if it exists. This flags is used to indicate the user just enabled
                 * a vendor that did not have any enabled configuration sets.
                 *
                 * @private
                 * @method _loadForceFlag
                 */
                var _loadForceFlag = function() {
                    var value = $location.search().force;
                    if (value) {
                        $scope.force = PARSE.parseBoolean(value);
                    } else {
                        $scope.force = false;
                    }
                };

                /**
                 * Load the vendor from the server
                 *
                 * @private
                 * @method _loadVendorFromServer
                 */
                var _loadVendorFromServer = function() {
                    _loadForceFlag();

                    // Not passed from a parent controller, so do it ourselves
                    var id = $location.search().id;
                    if (id) {
                        $scope.fetch(id);
                    } else {

                        // failure
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system failed to pass the ID query string parameter."),
                            id: "errorInvalidParameterId"
                        });
                    }
                };

                /**
                 * Load the vendor from the parent passed data
                 *
                 * @private
                 * @method _loadVendorFromParent
                 */
                var _loadVendorFromParent = function() {
                    $scope.serverRequest = true;
                    _loadForceFlag();

                    if ($scope.$parent.vendor &&
                        $scope.$parent.vendor.configs) {
                        $scope.configs = $scope.$parent.vendor.configs;
                        $scope.serverRequest = false;
                        _updateTotals();
                    }
                };


                /**
                 * Updates the totalEnabled/totalDisabled counts.
                 *
                 * @method _updateTotals
                 */
                var _updateTotals = function() {
                    var totalEnabled = 0;
                    $scope.configs.forEach(function(config) {
                        if (config.enabled) {
                            totalEnabled++;
                        }
                    });

                    $scope.totalEnabled = totalEnabled;
                    $scope.totalDisabled = $scope.configs.length - totalEnabled;
                };

                // Setup a watch to recreate the filter expression if the user changes it.
                $scope.$watch("filter", function(newValue, oldValue) {
                    if (newValue) {
                        newValue = newValue.replace(/([.*+?^${}()|\[\]\/\\])/g, "\\$1"); // Escape any regex special chars (from MDN)
                        $scope.filterExpression = new RegExp(newValue, "i");
                    } else {
                        $scope.filterExpression = null;
                    }
                });

                /**
                 * Sync. filter the configs by the optional filer expression built from the filter field.
                 *
                 * @method filterConfigs
                 * @param  {String} value
                 * @return {Boolean}
                 */
                $scope.filterConfigs = function(value) {
                    return $scope.filterExpression ?
                        $scope.filterExpression.test(value.config) ||
                                (value.exception && $scope.filterExpression.test(value.exception))  :
                        true;
                };

                /**
                 * Clears the filter when the Esc key
                 * is pressed.
                 *
                 * @scope
                 * @method triggerClearFilter
                 * @param {Event} event - The event object
                 */
                $scope.triggerClearFilter = function(event) {
                    if (event.keyCode === 27) {
                        $scope.clearFilter();
                    }
                };

                /**
                 * Clear the filter.
                 *
                 * @method clearFilter
                 */
                $scope.clearFilter = function() {
                    $scope.filter = "";
                };

                /**
                 * Clear the filter only if there is one defined.
                 *
                 * @method toggleFilter
                 */
                $scope.toggleFilter = function() {
                    if ($scope.filter) {
                        $scope.clearFilter();
                    }
                };

                /**
                 * Fetch a vendor by its vendor id.
                 *
                 * @method fetch
                 * @param  {String} id Vendor id.
                 * @return {Promise}   Promise that when fulfilled will have loaded the vendor
                 */
                if (!$scope.vendor) {

                    // Only installed if not passed from the parent controller.
                    $scope.fetch = function(id) {
                        $scope.serverRequest = true;
                        spinnerAPI.start("loadingSpinner2");
                        return vendorService
                            .fetchVendorById(id)
                            .then(function(vendor) {
                                $scope.vendor = vendor;
                                $scope.configs = vendor.configs;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetchRulesList"
                                });

                            }).finally(function() {
                                $scope.serverRequest = false;
                                _updateTotals();
                                spinnerAPI.stop("loadingSpinner2");
                            });
                    };
                }

                /**
                 * Enable or disable a specific config by its path stored in the config.config property.
                 *
                 * @method setConfig
                 * @private
                 * @param  {Object} config      Configuration object
                 * @return {Promise}            Promise that when fulfilled will disable/enable the requested config.
                 */
                $scope.setConfig = function(config) {
                    var operation = config.enabled ? "enable" : "disable";

                    // Get a boolean to set config.enabled later
                    var enabling = operation === "enable";

                    // Full strings are provided here to aid localization
                    var message = enabling ?
                        LOCALE.maketext("You have successfully enabled the configuration file: [_1]", config.config) :
                        LOCALE.maketext("You have successfully disabled the configuration file: [_1]", config.config);

                    spinnerAPI.start("loadingSpinner2");
                    config.serverRequest = true;
                    return vendorService
                        [operation + "Config"](config.config) // e.g. enableConfig or disableConfig
                        .then(function() {
                            _clearIssues();
                            config.enabled = enabling;
                            if (config.exception) {
                                delete config.exception;
                            }

                            // Report success
                            alertService.add({
                                type: "success",
                                message: message,
                                id: operation + "OneSuccess"
                            });
                        }, function(error) {
                            config.enabled = !enabling;
                            config.exception = error;
                        }).finally(function() {
                            _updateIssues();
                            _updateTotals();
                            delete config.serverRequest;
                            spinnerAPI.stop("loadingSpinner2");
                        });
                };

                /**
                 * Update the configs from the outcomes. When this is done processing, the configs collection
                 * state is updated to reflect the current state on the server. Also, if any config outcome fails,
                 * the property .exception property on the specific config is filled in with the issue related to that
                 * failure so the UI can report it directly.
                 *
                 * @private
                 * @method _updateConfigs
                 * @param  {Array} configs   Collection of configs for this vendor
                 * @param  {Array} outcomes  Collection of outcome for an enable/disable all action.
                 */
                var _updateConfigs = function(configs, outcomes) {
                    angular.forEach(outcomes, function(outcome) {
                        var match = _.find(configs, function(config) {
                            return config.config === outcome.config;
                        });
                        match.enabled = outcome.enabled;
                        if (!outcome.ok) {
                            match.exception = outcome.exception;
                        } else if (match.exception) {
                            delete match.exception;
                        }
                    });
                };

                /**
                 * Update the issues flag
                 *
                 * @private
                 * @method _updateIssues
                 */
                var _updateIssues = function() {
                    var match = _.find($scope.configs, function(config) {
                        return !!config.exception;
                    });
                    $scope.hasIssues = typeof (match) !== "undefined";
                };

                /**
                 * Test if the config has a related issue meaning something went wrong.
                 *
                 * @method hasIssue
                 * @return {Boolean} true if there are any issues, false otherwise.
                 */
                $scope.hasIssue = function(config) {
                    return !!config.exception;
                };

                /**
                 * Clear the issues property in preparation for an api run.
                 *
                 * @private
                 * @method _clearIssues
                 */
                var _clearIssues = function() {
                    delete $scope.hasIssues;
                };

                /**
                 * Attempt to enabled all the configs for this vendor.
                 *
                 * @method enableAllConfigs
                 * @return {Promise} A promise that when fulfilled will enable all the configs that can be successfully
                 * enabled. The actual outcome are passed to the success handler.
                 */
                $scope.enableAllConfigs = function() {
                    return _modifyAllConfigs("enable");
                };

                /**
                 * Attempt to disabled all the configs for this vendor.
                 *
                 * @method disableAllConfigs
                 * @return {Promise} A promise that when fulfilled will disable all the configs that can be successfully
                 * enabled. The actual outcome are passed to the success handler.
                 */
                $scope.disableAllConfigs = function() {
                    return _modifyAllConfigs("disable");
                };

                /**
                 * Attempts to enable/disable all of the configs for this vendor.
                 *
                 * @method _modifyAllConfigs
                 * @private
                 * @param  {String} operation   The operation being performed on all configs, i.e. "enable" or "disable"
                 * @return {Promise}            Upon success all configs will have been modified appropriately.
                 *                              Outcomes are passed to both the success and failure handlers.
                 */
                function _modifyAllConfigs(operation) {

                    // Short circuit if no operation is necessary
                    if ((operation === "enable" && $scope.totalDisabled === 0) ||
                       (operation === "disable" && $scope.totalEnabled === 0)) {
                        return;
                    }

                    // Full strings are provided here to aid localization
                    var messages = {
                        disable: {
                            success: LOCALE.maketext("You have successfully disabled all of the configuration files."),
                            partial: LOCALE.maketext("You have successfully disabled some of the configuration files. The files that the system failed to disable are marked below."),
                            failure: LOCALE.maketext("The system could not disable the configuration files.")
                        },
                        enable: {
                            success: LOCALE.maketext("You have successfully enabled all of the configuration files."),
                            partial: LOCALE.maketext("You have successfully enabled some of the configuration files. The files that the system failed to enable are marked below."),
                            failure: LOCALE.maketext("The system could not enable the configuration files.")
                        }
                    };

                    // Begin working with the promise
                    spinnerAPI.start("loadingSpinner2");
                    $scope.serverRequest = true;
                    return vendorService
                        [operation + "AllConfigs"]($scope.vendor.vendor_id) // e.g. enableAllConfigs or disableAllConfigs
                        .then(function(outcomes) {
                            _clearIssues();
                            _updateConfigs($scope.configs, outcomes.configs);

                            // Report success
                            alertService.add({
                                type: "success",
                                message: messages[operation].success,
                                id: operation + "AllSuccess"
                            });

                        }, function(outcomes) {
                            _clearIssues();

                            if (outcomes.configs.length) {
                                _updateConfigs($scope.configs, outcomes.configs);
                                alertService.add({
                                    type: "warning",
                                    message: messages[operation].partial,
                                    id: operation + "AllWarning"
                                });
                            } else {
                                alertService.add({
                                    type: "danger",
                                    message: messages[operation].failure,
                                    id: operation + "AllError"
                                });
                            }

                        }).finally(function() {
                            _updateIssues();
                            _updateTotals();
                            $scope.serverRequest = false;
                            spinnerAPI.stop("loadingSpinner2");
                        });
                }

                /**
                 * Determines if a button should be disabled.
                 *
                 * @param  {String}  type       The button type
                 * @param  {Boolean} loading    Generic loading flag
                 * @return {Boolean}            Should the button be disabled?
                 */
                $scope.buttonDisabled = function(type, loading) {
                    if ($scope.serverRequest) {
                        return true;
                    }

                    switch (type) {
                        case "enableAll":
                            return $scope.totalDisabled === 0;
                        case "disableAll":
                            return $scope.totalEnabled === 0;
                        case "configToggle":
                            return loading;
                    }
                };

                if ($scope.$parent.vendor) {

                    // we are embedded
                    $scope.$parent.$watch("vendor.configs", function() {
                        _loadVendorFromParent();
                    });
                }

                $scope.$on("$viewContentLoaded", function() {
                    _loadVendor();
                });

                _initializeView();
            }
        ]);
    }
);

/*
# templates/mod_security/views/addVendorController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/editVendorController',[
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "app/views/enableDisableConfigController",
        "cjt/filters/notApplicableFilter"
    ],
    function(angular, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller(
            "editVendorController", [
                "$scope",
                "$filter",
                "$routeParams",
                "spinnerAPI",
                "alertService",
                "vendorService",
                function(
                    $scope,
                    $filter,
                    $routeParams,
                    spinnerAPI,
                    alertService,
                    vendorService) {

                    /**
                         * Helper function to just make danger alerts a little more dense.
                         *
                         * @private
                         * @method _dangetAlert
                         * @param  {String} msg Message for the alert
                         * @param  {String} id  HTML ID requested from the alertService
                         */
                    function _dangerAlert(msg, id) {
                        alertService.add({
                            type: "danger",
                            message: msg,
                            id: id
                        });
                        $scope.scrollTo("top");
                    }

                    /**
                         * Loads the form with vendor meta-data from the WHM API.
                         *
                         * @method loadVendor
                         * @param  {String} vendorId This will correspond to the vendor_id field from the API
                         */
                    $scope.loadVendor = function(vendorId) {
                        if (!$routeParams["suppress-clear-alert"] ||
                                !PARSE.parseBoolean($routeParams["suppress-clear-alert"])) {
                            alertService.clear();
                        }

                        var promise;
                        if (vendorId) {
                            spinnerAPI.start("loadingSpinner");
                            promise = vendorService.fetchVendorById(vendorId)
                                .then(function success(data) {
                                    angular.extend($scope.vendor, data);
                                    $scope.vendor.report_url = $filter("na")($scope.vendor.report_url);
                                }, function failure(error) {
                                    _dangerAlert(error, "errorLoadVendorConfig");
                                });

                            promise["finally"](function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                        } else {
                            _dangerAlert(LOCALE.maketext("An error occurred in the attempt to retrieve the vendor information."), "errorNoVendorID");
                        }
                    };

                    /**
                         * Toggle the show/hide vendor details flag.
                         *
                         * @method toggleDetails
                         */
                    $scope.toggleDetails = function() {
                        $scope.hideDetails = !$scope.hideDetails;
                    };

                    // Initialize the form on first load.
                    $scope.isEditor = true;
                    $scope.hideDetails = true;
                    $scope.vendor = { id: $routeParams.id };

                    $scope.$on("$viewContentLoaded", function() {
                        $scope.loadVendor($scope.vendor.id);
                    });
                }
            ]
        );
    }
);

/*
# templates/mod_security/vendors.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/vendors',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {

        // First create the application
        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load first
            "ngRoute",
            "ui.bootstrap",
            "cjt2.whm"
        ]);

        // Then load the application dependencies
        var app = require(
            [
                "cjt/bootstrap",
                "cjt/util/locale",

                // Application Modules
                "cjt/views/applicationController",
                "app/views/commonController",
                "app/views/vendorListController",
                "app/views/addVendorController",
                "app/views/enableDisableConfigController",
                "app/views/editVendorController",
                "cjt/services/autoTopService",
                "cjt/services/whm/breadcrumbService",
                "cjt/services/whm/titleService"
            ], function(BOOTSTRAP, LOCALE) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.firstLoad = {
                    configs: true,
                    vendors: true
                };

                // routing
                app.config(["$routeProvider",
                    function($routeProvider) {

                        // List of vendors
                        $routeProvider.when("/vendors", {
                            controller: "vendorListController",
                            templateUrl: CJT.buildFullPath("mod_security/views/vendorListView.ptt"),
                            breadcrumb: LOCALE.maketext("Manage Vendors"),
                            title: LOCALE.maketext("Manage Vendors"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "vendors"
                        });

                        // Add a vendor
                        $routeProvider.when("/vendors/add", {
                            controller: "addVendorController",
                            templateUrl: CJT.buildFullPath("mod_security/views/addEditVendor.ptt"),
                            breadcrumb: LOCALE.maketext("Add Vendor"),
                            title: LOCALE.maketext("Add Vendor"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "add"
                        });

                        // Edit a vendor
                        $routeProvider.when("/vendors/edit", {
                            controller: "editVendorController",
                            templateUrl: CJT.buildFullPath("mod_security/views/addEditVendor.ptt"),
                            breadcrumb: LOCALE.maketext("Select Vendor Rule Sets"),
                            title: LOCALE.maketext("Select Vendor Rule Sets"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "edit"
                        });

                        $routeProvider.otherwise({
                            redirectTo: function(routeParams, path, search) {
                                return "/vendors?" + window.location.search;
                            }
                        });
                    }
                ]);

                app.run(["autoTopService", "breadcrumbService", "titleService", function(autoTopService, breadcrumbService, titleService) {

                    // Setup the automatic scroll to top for view changes
                    autoTopService.initialize();

                    // Setup the breadcrumbs service
                    breadcrumbService.initialize();

                    // Setup the title update service
                    titleService.initialize();
                }]);

                BOOTSTRAP(document);
            });

        return app;
    }
);

