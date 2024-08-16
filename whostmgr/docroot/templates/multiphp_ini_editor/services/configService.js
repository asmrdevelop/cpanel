/*
 * templates/multiphp_ini_editor/services/configService.js Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
        "cjt/util/locale",

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST, APIDRIVER, LOCALE) {
        "use strict";

        var app = angular.module("whm.multiPhpIniEditor.configService", []);

        /**
         * Converts the response to our application data structure
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function convertResponseToList(response) {
            var items = [];
            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var list = data[i];
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
        }

        /**
         * Setup the account list model's API service
         */
        app.factory("configService", ["$q", function($q) {

            // return the factory interface
            return {

                /**
                 * Get a list of directives for the selected PHP version.
                 * @param {string} version - Selected PHP version
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchBasicList: function(version) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_get_directives");
                    apiCall.addArgument("version", version);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

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
                 * Set the new settings of basic directives for the selected PHP version.
                 * setData: JSON object with the list of PHP directives and their corresponding settings.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                applySettings: function(version, directives) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_set_directives");
                    apiCall.addArgument("version", version);

                    // Construct the directive & value arguments.
                    if (typeof (directives) !== "undefined" && directives.length > 0) {
                        directives.forEach(function(directive, index) {
                            apiCall.addArgument("directive-" + index, directive.key + ":" + directive.value);
                        });
                    }

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

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
                 * Get the content of the INI file for the selected PHP version.
                 * @param {string} version - Selected PHP version
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchContent: function(version) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_get_content");
                    apiCall.addArgument("version", version);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {

                                // Keep the promise
                                deferred.resolve(response.data.content);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Save the new edited content of the INI file for the selected PHP version.
                 * version: The selected PHP version.
                 * content: The edited content.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                saveIniContent: function(version, content) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_set_content");
                    apiCall.addArgument("version", version);
                    apiCall.addArgument("content", content);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

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
                 * Helper method that calls convertResponseToList to prepare the data structure
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
                 * Validates a PHP directive value depeding on the directive type.
                 * @param  {string} type - The type of the directive (Integer/Float/String)
                 * @param  {string} value - The value of the directive (Integer/Float/String)
                 * @return {Object} Validation data.
                 */
                validateBasicDirective: function(type, value) {
                    var text = value || "";
                    var valid = true;
                    var valMsg = "";
                    if (type === "integer") {

                        // Do the integer thing.
                        var E_FLAG = "[~!]?\\s*E_(?:(?:(?:CORE_|COMPILE_|USER_)?(?:ERROR|WARNING))|(?:USER_)?(?:NOTICE|DEPRECATED)|PARSE|STRICT|RECOVERABLE_ERROR|ALL)";
                        var E_OPER = "[&|^]";
                        var intRegex = new RegExp("^\\s*" + E_FLAG + "(?:\\s*" + E_OPER + "\\s*" + E_FLAG + ")*$");
                        if (/^-?\d+[kmg]?$/i.test(text) || intRegex.test(text)) {
                            valid = true;
                        } else {
                            valid = false;
                            valMsg = LOCALE.maketext("You must provide either an integer value, a [output,url,_1,shorthand byte,target,blank,title,shorthand byte documentation], or a [output,url,_2,predefined constant,target,blank,title,predefined constant documentation].", "http://php.net/manual/en/faq.using.php#faq.using.shorthandbytes", "http://php.net/manual/en/errorfunc.constants.php");
                        }
                    } else if (type === "float") {
                        if (/^-?\d+(?:\.\d*)?$/.test(text)) {
                            valid = true;
                        } else {
                            valid = false;
                            valMsg = LOCALE.maketext("You must provide a valid float value.");
                        }
                    }
                    return {
                        valid: valid,
                        valMsg: valMsg
                    };
                }
            };
        }]);
    }
);
