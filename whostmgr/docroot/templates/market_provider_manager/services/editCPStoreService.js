/*
# templates/ssl_provider_manager/services/editCPStoreService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
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
        var commission_config;

        function editCPStoreServiceFactory($q) {
            var editCPStoreService = {};

            editCPStoreService.set_commission_id = function(provider, commission_id) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "set_market_provider_commission_id");
                apiCall.addArgument("provider", provider);
                apiCall.addArgument("commission_id", commission_id);
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

            editCPStoreService.fetch_market_providers_commission_config = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_market_providers_commission_config");
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
                    commission_config = result.data;
                });

                return deferred.promise;
            };

            editCPStoreService.get_market_providers_commission_config = function() {
                return commission_config;
            };

            return editCPStoreService;
        }


        editCPStoreServiceFactory.$inject = ["$q"];
        return app.factory("editCPStoreService", editCPStoreServiceFactory);
    }
);
