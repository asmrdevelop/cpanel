/*
# feature/services/featureListService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [

        // Libraries
        "angular",
        "lodash",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, _, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * Setup the feature list models API service
         */
        app.factory("featureListService", ["$q", "APIService", "PAGE", function($q, APIService, PAGE) {

            /**
             * Converts the response to our application data structure
             *
             * @method convertResponseToList
             * @private
             * @param  {Object} response
             * @return {Object} Sanitized data structure.
             */
            function convertResponseToList(response) {
                var items = [];
                if (response.status) {
                    var data = response.data;
                    for (var i = 0, length = data.length; i < length; i++) {
                        items.push(data[i]);
                    }

                    var meta = response.meta;

                    var totalItems = meta.paginate.total_records || data.length;
                    var totalPages = meta.paginate.total_pages || 1;

                    return {
                        items: items,
                        totalItems: totalItems,
                        totalPages: totalPages,
                        status: response.status
                    };
                } else {
                    return {
                        items: [],
                        totalItems: 0,
                        totalPages: 0,
                        status: response.status
                    };
                }
            }

            /**
             * Helper method to retrieve feature lists in chained actions
             *
             * @method _fetchLists
             * @private
             * @param  {Deferred} deferred
             * @return {Promise}
             */
            function _fetchLists(deferred) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "get_featurelists");
                apiCall.addSorting("", "asc", "lexicographic_caseless");

                this.deferred(apiCall, {
                    transformAPISuccess: convertResponseToList
                }, deferred);

                // pass the promise back to the controller
                return deferred.promise;
            }

            /**
             * Helper method to save addon feature lists in chained actions
             *
             * @method _saveAddons
             * @private
             * @param  {Deferred} deferred
             * @param  {String} name The name of the base featurelist calling this chained action
             * @param  {Array} list The Array of addons features to be saved
             * @return {Promise}
             */
            function _saveAddons(deferred, name, list) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "update_featurelist");
                apiCall.addArgument("featurelist", name + ".cpaddons");

                _.each(list, function(feature) {
                    apiCall.addArgument(feature.name, feature.value);
                });

                this.deferred(apiCall, {}, deferred);

                // pass the promise back to the controller
                return deferred.promise;
            }

            // Set up the service's constructor and parent
            var FeatureListService = function() {};
            FeatureListService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(FeatureListService.prototype, {

                /**
                 * Get a list of feature lists
                 *
                 * @method loadFeatureLists
                 * @return {Promise} Promise that will fulfill the request.
                 * @throws Error
                 */
                loadFeatureLists: function() {
                    var deferred = $q.defer();

                    // pass the promise back to the controller
                    return _fetchLists.call(this, deferred);
                },

                /**
                 * Get a single feature list by its name from the backend and merges
                 * it with the list of descriptions
                 *
                 * @method load
                 * @param {String} name The name of a feature list to fetch.
                 * @param {Array} dictionary Array of human readable labels for feature names.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                load: function(name, dictionary) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "get_featurelist_data");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        apiSuccess: function(response, deferred) {
                            response.items = [];

                            // legacy features only supported by x and x2 interfaces
                            var legacyNames = ["bbs", "chat", "cpanelpro_support", "searchsubmit", "advguest", "guest", "cgi", "scgiwrap", "counter", "entropybanner", "entropysearch", "clock", "countdown", "randhtml", "videotut", "getstart"],
                                featurePluginFlag = false,
                                featureAddonFlag = false,
                                legacyFeature,
                                featureLabel,
                                featureID,
                                featureState;

                            _.each(response.data.features, function(feature) {

                                legacyFeature = false;
                                if ( _.includes(legacyNames, feature.id) ) {
                                    if ( PAGE.legacySupport ) {
                                        legacyFeature = true;
                                    } else {

                                        // exclude legacy feature
                                        return;
                                    }
                                }

                                if ( feature.id === "fantastico" && !PAGE.fantasticoSupport ) {

                                    // exclude fantastico feature
                                    return;
                                }

                                // check the dictionary for additional meta data about the feature
                                featureID = feature.id;
                                featureLabel = feature.id;
                                if ( feature.id in dictionary ) {
                                    featureLabel = dictionary[feature.id].name;
                                    featurePluginFlag = dictionary[feature.id].is_plugin === "1" ? true : false;
                                    featureAddonFlag = dictionary[feature.id].is_cpaddon === "1" ? true : false;
                                }

                                // handle api oddities for disabled list
                                featureState = false;
                                if ( name === "disabled" ) {
                                    if ( feature.value === "0" ) {
                                        featureState = true;
                                    }
                                } else {
                                    featureState = feature.value === "1" ? true : false;
                                }

                                response.items.push({
                                    name: featureID,
                                    label: featureLabel,
                                    value: featureState,
                                    legacy: legacyFeature,
                                    disabled: feature.is_disabled === "1" ? true : false,
                                    plugin: featurePluginFlag,
                                    addon: featureAddonFlag
                                });
                            }, response.data.features);

                            // sort features by the readable labels
                            response.items = _.sortBy(response.items, function(feature) {
                                return feature.label.toLowerCase();
                            });

                            deferred.resolve(response);
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Saves the states of a list of a features
                 *
                 * @method save
                 * @param {String} name The name of a feature list to save.
                 * @param {Array} list The array of list objects to save.

                 * @return {Promise} Promise that will fulfill the request.
                 */
                save: function(name, list) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "update_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var addons = [], featureList = angular.copy(list);
                    _.each(featureList, function(feature) {

                        // conditionally flip the logic from the checkboxes
                        if ( name === "disabled" ) {
                            feature.value = feature.value === true ? "0" : "1";
                        } else {
                            feature.value = feature.value === true ? "1" : "0";
                        }

                        if ( feature.addon ) {
                            addons.push(feature);
                        } else {
                            apiCall.addArgument(feature.name, feature.value);
                        }
                    });

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function() {
                            _saveAddons.call(this, deferred, name, addons);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Add a feature list
                 *
                 * @method add
                 * @param {String} name The name of the feature list to be created
                 * @return {Promise} Promise that will fulfill the request.
                 */
                add: function(name) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "create_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function(response) {
                            deferred.resolve(response);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Delete a feature list by its name
                 *
                 * @method remove
                 * @param  {String} name The name of the feature list to delete.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                remove: function(name) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "delete_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function() {
                            deferred.notify();
                            _fetchLists.call(this, deferred);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                *
                * @method  prepareList
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return convertResponseToList(response);
                }
            });

            return new FeatureListService();
        }]);
    }
);
