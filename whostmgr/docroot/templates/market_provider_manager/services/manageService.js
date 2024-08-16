/*
# templates/ssl_provider_manager/services/manageService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    [
        "angular",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, API, APIREQUEST) {

        var app = angular.module("App");
        var NO_MODULE = "";

        function manageServiceFactory($q, PAGE) {
            var manageService = {};
            var providers = [];// eslint-disable-line no-unused-vars
            var products = [];
            var CONTACTEMAIL = "";

            manageService.get_providers = function() {
                if (PAGE.providers) {
                    return PAGE.providers;
                } else {
                    return [];
                }
            };

            manageService.get_products = function() {
                return products;
            };

            manageService.fetch_providers = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_market_providers_list");
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    providers = result.data;
                });
                return deferred.promise;
            };

            manageService.fetch_products = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_market_providers_products");
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    products = result.data;
                });
                return deferred.promise;
            };

            manageService.set_provider_enabled_status = function(provider, enabled) {
                var deferred = $q.defer();

                var api_function = enabled ? "enable_market_provider" : "disable_market_provider";
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, api_function);
                apiCall.addArgument("name", provider.name);
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            manageService.get_contact_email = function() {
                return CONTACTEMAIL;
            };

            manageService.fetch_contact_email = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_tweaksetting");
                apiCall.addArgument("key", "CONTACTEMAIL");
                apiCall.addArgument("module", "Basic");
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    CONTACTEMAIL = result.data.tweaksetting.value;
                });
                return deferred.promise;
            };

            return manageService;
        }

        manageServiceFactory.$inject = ["$q", "PAGE"];
        return app.factory("manageService", manageServiceFactory);
    }
);
