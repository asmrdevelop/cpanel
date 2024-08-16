/*
# mod_security/services/configService.js          Copyright(c) 2020 cPanel, L.L.C.
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
         * Apply the defaults to the config if needed.
         * @param  {Array} configs
         */
        function applyDefaults(config) {
            if (config.default && config.missing) {
                if (config.type === "number") {
                    config.state = parseInt(config.default, 10);
                } else {
                    config.state = config.default;
                }
            }
        }

        /**
         * Converts the response to our application data structure
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
                    var config = data[i];

                    // Clean up the boolean data
                    if (typeof (config.engine) !== "undefined") {
                        config.engine = PARSE.parsePerlBoolean(config.engine);
                    }

                    // Apply the default if the config is missing
                    applyDefaults(config);

                    // Mark the record as unchanged
                    config.changed = false;

                    items.push(
                        config
                    );
                }

                return items;
            } else {
                return [];
            }
        }

        /**
         * Setup the configuration models API service
         */
        app.factory("configService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var ConfigService = function() {};
            ConfigService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(ConfigService.prototype, {

                /**
                 * Get a list of mod_security rule hits that match the selection criteria passed in meta parameter
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_settings");
                    var deferred = this.deferred(apiCall, { transformAPISuccess: convertResponseToList });
                    return deferred.promise;
                },

                /**
                 * Save the changed configurations.
                 * @param  {Array} configs
                 * @return {Promise} Promise that will fulfill the request.
                 */
                save: function(configs) {
                    if (!configs) {
                        return;
                    }

                    var toSave = [];
                    for (var i = 0, l = configs.length; i < l; i++) {
                        if (configs[i].changed) {
                            toSave.push(configs[i]);
                        }
                    }

                    if (toSave.length > 0 ) {

                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "modsec_batch_settings");
                        for (var j = 0, jl = toSave.length; j < jl; j++) {
                            var item = toSave[j];
                            if (
                                (!item.engine && item.default && (                                                        // Not an engine and has a default
                                    ((item.type === "text" || item.type === "radio") && (item.state === item.default)) || // Text or radio field with a default set to default, but not missing from file
                                    (item.type === "number" && (parseInt(item.state, 10) === item.default))               // Number field with a default set to default, but not missing from file
                                )) ||
                                (item.state === "") // Text or number that has been cleared, but isn't missing from file
                            ) {
                                if (!item.missing) {
                                    apiCall.addArgument("setting_id", toSave[j].setting_id, true);
                                    apiCall.addArgument("remove", 1, true);

                                    // Otherwise, nothing to do here.
                                }
                            } else {
                                apiCall.addArgument("setting_id", toSave[j].setting_id, true);
                                apiCall.addArgument("state", item.state, true);
                            }
                            apiCall.incrementAuto();
                        }
                        apiCall.addArgument("commit", 1);

                        var deferred = this.deferred(apiCall, {
                            apiSuccess: function(response, deferred) {
                                for (var i = 0, l = configs.length; i < l; i++) {
                                    if (configs[i].changed) {
                                        configs[i].changed = false;
                                    }
                                }

                                deferred.resolve(response.data);
                            },
                            apiFailure: function(response) {

                                // TODO: Get the list from the data
                                deferred.reject(response.error);
                            }
                        });

                        // pass the promise back to the controller
                        return deferred.promise;
                    }
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return convertResponseToList(response);
                },

                /**
                 * Apply the defaults to the config if needed.
                 * @param  {Array} configs
                 */
                applyDefaults: applyDefaults
            });

            return new ConfigService();
        }]);
    }
);
