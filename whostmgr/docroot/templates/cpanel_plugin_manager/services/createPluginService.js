/*
# cpanel_plugin_manager/services/createPluginService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W055 */

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
         * Setup the configuration models API service
         */
        return app.factory("createPluginService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var createPluginService = function() {

            };

            createPluginService.prototype = {

                /**
                 * Generates the plugin file for the given input.
                 * @method generatePluginFile
                 * @param  {object} pluginData Has all the data necessary for plugin file creation.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                generatePluginFile: function(pluginData) {
                    if (pluginData !== undefined && pluginData.name !== "" ) {

                        var apiCall = new APIREQUEST.Class();
                        var deferred = $q.defer();

                        apiCall.initialize(NO_MODULE, "generate_cpanel_plugin");
                        apiCall.addArgument("plugin_name", pluginData.name);
                        apiCall.addArgument("install.json", pluginData.installListJson);
                        apiCall.addArgument("icons.json", pluginData.iconListJson);

                        API.promise(apiCall.getRunArguments()).
                            done(function(response) {
                                response = response.parsedResponse;
                                if (response.status) {
                                    deferred.resolve(response.data);
                                } else {
                                    deferred.reject(response.error);
                                }
                            });

                        return deferred.promise;
                    }
                }
            };

            return new createPluginService();
        }]);
    }
);
