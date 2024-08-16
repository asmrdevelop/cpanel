/*
# templates/ssl_provider_manager/services/editProductsService.js Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/util/parse",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, API, QUERY, cjt2Parse, APIREQUEST) {

        "use strict";

        var app = angular.module("App");
        var NO_MODULE = "";

        function editProductsServiceFactory($q) {
            var editProductsService = {};
            var products = [];
            var productsMetadata = [];

            editProductsService.get_products = function() {
                return products;
            };

            editProductsService.fetch_products = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_adjusted_market_providers_products");
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

                    // Typecast the responses.
                    products.forEach( function(p) {
                        ["recommended", "x_ssl_per_domain_pricing"].forEach(
                            function(attr) {
                                p[attr] = cjt2Parse.parsePerlBoolean(p[attr]);
                            }
                        );

                        p.price = p.price && cjt2Parse.parseNumber(p.price);

                        if (p.x_ssl_per_domain_pricing) {
                            p.x_price_per_domain = cjt2Parse.parseNumber(p.x_price_per_domain);
                        }
                    } );
                });

                return deferred.promise;
            };

            editProductsService.set_product_enabled = function(product, provider, enabled) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                var enabled_value = enabled ? 1 : 0;

                apiCall.initialize(NO_MODULE, "set_market_product_attribute");
                apiCall.addArgument("product_id", product.product_id);
                apiCall.addArgument("value", enabled_value);
                apiCall.addArgument("provider", provider);
                apiCall.addArgument("attribute", "enabled");
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

            editProductsService.setMarketProductAttribute = function(providerID, productID, attribute, value) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "set_market_product_attribute");
                apiCall.addArgument("product_id", productID);
                apiCall.addArgument("provider", providerID);
                apiCall.addArgument("attribute", attribute);
                apiCall.addArgument("value", value);
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

            editProductsService.set_provider_product_recommended = function(product, provider, recommended) {
                var deferred = $q.defer();

                var recommended_value = recommended ? 1 : 0;

                var need_to_disable = recommended_value && products.filter( function(p) {
                    return ( !!p.recommended && product.product_group === p.product_group );
                } );

                var apiCall = new APIREQUEST.Class();

                // XXX FIXME HACK HACK improve once we have batch
                if (need_to_disable && need_to_disable.length) {
                    apiCall.initialize(NO_MODULE, "batch");

                    var calls = {};
                    need_to_disable.forEach( function(p, i) {
                        calls["command-" + i] = {
                            product_id: p.product_id,
                            value: 0,
                            provider: p.provider_name
                        };
                    } );

                    calls["command-" + need_to_disable.length] = {
                        product_id: product.product_id,
                        value: 1,
                        provider: product.provider_name
                    };

                    for (var query_key in calls) {
                        if ( calls.hasOwnProperty(query_key) ) {
                            calls[query_key].attribute = "recommended";

                            // calls[query_key].version = 1;

                            var this_call_query = QUERY.make_query_string( calls[query_key] );
                            apiCall.addArgument(query_key, "set_market_product_attribute?" + this_call_query);
                        }
                    }
                } else {
                    apiCall.initialize(NO_MODULE, "set_market_product_attribute");
                    apiCall.addArgument("product_id", product.product_id);
                    apiCall.addArgument("value", recommended_value);
                    apiCall.addArgument("provider", provider);
                    apiCall.addArgument("attribute", "recommended");
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

            editProductsService.fetch_product_metadata = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize(NO_MODULE, "get_market_providers_product_metadata");
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
                    productsMetadata = result.data;

                    productsMetadata.forEach( function(m) {
                        for (var attr in m.attributes) {
                            if (m.attributes.hasOwnProperty(attr)) {
                                m.attributes[attr].read_only = cjt2Parse.parsePerlBoolean(m.attributes[attr].read_only);
                            }
                        }
                    } );
                });
                return deferred.promise;
            };

            editProductsService.get_product_metadata = function() {
                return productsMetadata;
            };

            return editProductsService;
        }

        editProductsServiceFactory.$inject = ["$q"];
        return app.factory("editProductsService", editProductsServiceFactory);
    }
);
