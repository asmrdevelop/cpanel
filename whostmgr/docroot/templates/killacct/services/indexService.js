/*
# templates/tls_wizard_redirect/services/indexService.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/util/query", // XXX FIXME remove when batch is in
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, API, QUERY, APIREQUEST) {

        var app = angular.module("App");
        var NO_MODULE = "";

        function indexServiceFactory($q, PAGE) {
            var indexService = {};
            indexService.get_domains = function() {
                return PAGE.data.domains;
            };

            indexService.remove_account = function(account) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "removeacct");
                apiCall.addArgument("user", account.username);
                apiCall.addArgument("keepdns", account.keep_dns ? "1" : "0");
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

            indexService.get_account_summary = function(username) {

                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "accountsummary");
                apiCall.addArgument("user", username);
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

            return indexService;
        }

        indexServiceFactory.$inject = ["$q", "PAGE"];
        return app.factory("indexService", indexServiceFactory);
    });
