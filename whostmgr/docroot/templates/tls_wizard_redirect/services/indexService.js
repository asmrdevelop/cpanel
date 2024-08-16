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
        "cjt/util/query",   // XXX FIXME remove when batch is in
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

            indexService.get_enabled_provider_count = function() {
                return PAGE.data.enabled_provider_count;
            };

            indexService.get_default_theme = function() {
                return PAGE.data.default_theme;
            };

            indexService.check_account_has_feature = function(username, feature) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "verify_user_has_feature");
                apiCall.addArgument("user", username);
                apiCall.addArgument("feature", feature);
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

            indexService.check_user_has_features = function(user, features) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "batch");

                var calls = {};
                features.forEach( function(p, i) {
                    calls["command-" + i] = {
                        feature: p,
                    };
                } );

                for (var query_key in calls) {
                    if ( calls.hasOwnProperty(query_key) ) {
                        calls[query_key].user = user;

                        var this_call_query = QUERY.make_query_string( calls[query_key] );
                        apiCall.addArgument(query_key, "verify_user_has_feature?" + this_call_query);
                    }
                }

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

            indexService.force_enable_features_for_user = function(user, features) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "add_override_features_for_user");
                apiCall.addArgument("user", user);
                apiCall.addArgument("features", JSON.stringify(features));
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

            indexService.create_user_session = function(user) {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "create_user_session");
                apiCall.addArgument("user", user);
                apiCall.addArgument("service", "cpaneld");
                apiCall.addArgument("app", "SSL_TLS_Wizard");
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

            indexService.enable_cpstore_provider = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "enable_market_provider");
                apiCall.addArgument("name", "cPStore");
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

            indexService.set_user_theme_to_default_theme = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                var defaultTheme = PAGE.data.default_theme;

                apiCall.initialize(NO_MODULE, "modifyacct");
                apiCall.addArgument("user", user);
                apiCall.addArgument("RS", defaultTheme);
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

            indexService.set_user_style_to_retro = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "cpanel");
                apiCall.addArgument("user", user);
                apiCall.addArgument("cpanel_jsonapi_apiversion", "3");
                apiCall.addArgument("cpanel_jsonapi_module", "Styles");
                apiCall.addArgument("cpanel_jsonapi_func", "update");
                apiCall.addArgument("name", "retro");
                apiCall.addArgument("type", "default");
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


            indexService.get_user_account_info = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "accountsummary");
                apiCall.addArgument("user", user);
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
