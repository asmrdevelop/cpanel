/*
# templates/ssl_provider_manager/services/manageService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    'app/services/manageService',[
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

/*
# templates/ssl_provider_manager/services/editProductsService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/services/editProductsService',[
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

/*
# templates/ssl_provider_manager/services/editCPStoreService.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/services/editCPStoreService',[
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

/*
# templates/ssl_provider_manager/views/manageController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/manageController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/validator/email-validator",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "manageController", [
                "$scope",
                "manageService",
                "editCPStoreService",
                "growl",
                function($scope, manageService, editCPStoreService, growl) {
                    function _growl_error(error) {
                        return growl.error( _.escape(error) );
                    }

                    $scope.set_provider = function(provider, enabled) {
                        var enable_message = LOCALE.maketext("The system successfully enabled the Market provider “[_1]”.", _.escape(provider.name));
                        var disabled_message = LOCALE.maketext("The system successfully disabled the Market provider “[_1]”.", _.escape(provider.name));
                        var success_message = enabled ? enable_message : disabled_message;

                        return manageService.set_provider_enabled_status(provider, enabled).then(function() {
                            growl.success(success_message);

                            if (enabled && provider.supports_commission) {
                                var promise = check_for_commission_id_and_set_if_does_not_exist(provider.name);
                                return promise.then(function(success) {
                                    provider.enabled = enabled;
                                    $scope.$parent.go("edit_cpstore_config", 2);
                                }, function(error) {
                                    provider.enabled = enabled;
                                    $scope.$parent.go("edit_cpstore_config", 2);
                                });
                            } else {
                                provider.enabled = enabled;
                            }
                        }, _growl_error);
                    };

                    var check_for_commission_id_and_set_if_does_not_exist = function(provider) {
                        return editCPStoreService.fetch_market_providers_commission_config().then(function(success) {
                            var provider_needs_commission_id = false;
                            for (var x = 0; x < success.data.length; x++ ) {
                                if (success.data[x].provider_name === provider && !success.data[x].remote_commission_id) {
                                    provider_needs_commission_id = true;
                                }
                            }
                            if ( provider_needs_commission_id && $scope.CONTACTEMAIL ) {

                                // if no remote commission id, set one, otherwise we're done
                                return editCPStoreService.set_commission_id(provider, $scope.CONTACTEMAIL).then(function(success) {
                                    growl.success(LOCALE.maketext("The system successfully set the commission [asis,ID] for the provider “[_1]” to “[_2]”.", _.escape(provider), _.escape($scope.CONTACTEMAIL)));
                                }, function(error) {

                                    // We silence errors because they just might not be able to set it to an email
                                });
                            }
                        }, _growl_error);
                    };

                    $scope.init = function() {
                        $scope.fetching_products = true;
                        $scope.locale = LOCALE;
                        $scope.providers = manageService.get_providers();
                        $scope.$parent.loading = true;

                        manageService.fetch_products().then(function(result) {
                            angular.forEach(result.meta.warnings, function(value) {
                                growl.warning( _.escape(value) );
                            });
                            $scope.products = manageService.get_products();
                        }, _growl_error).finally(function() {
                            if ($scope && $scope.$parent) {
                                $scope.$parent.loading = false;
                            }
                            $scope.fetching_products = false;

                        });

                        manageService.fetch_contact_email().then(function() {
                            $scope.CONTACTEMAIL = manageService.get_contact_email();
                        }, _growl_error);
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# templates/ssl_provider_manager/views/editProductsController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    'app/views/editProductsController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/validator/compare-validators",
        "cjt/validator/datatype-validators",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSwitchDirective",
    ],
    function(_, angular, LOCALE) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "editProductsController", [
                "$scope",
                "editProductsService",
                "growl",
                "$uibModal",
                "$log",
                "PAGE",
                function($scope, editProductsService, growl, $uibModal, $log, PAGE) {
                    function growlError(error) {
                        return growl.error( _.escape(error) );
                    }

                    var provider_commission = {};
                    $scope.provider_commission = provider_commission;

                    var modal;

                    var providers = PAGE.providers;
                    for (var p = 0; p < providers.length; p++) {
                        if ( providers[p].even_commission_divisor ) {
                            provider_commission[providers[p].name] = providers[p].even_commission_divisor / 100;
                        }
                    }

                    $scope.set_product = function(product, enabled) {
                        var enable_message = LOCALE.maketext("The system has successfully enabled the product “[_1]”.", _.escape(product.display_name));
                        var disabled_message = LOCALE.maketext("The system has successfully disabled the product “[_1]”.", _.escape(product.display_name));
                        var success_message = enabled ? enable_message : disabled_message;

                        return editProductsService.set_product_enabled(product, product.provider_name, enabled).then(function() {
                            growl.success(success_message);
                            product.enabled = enabled;
                        }, growlError);
                    };

                    $scope.product_group_changing = {};

                    $scope.set_recommended = function(product, recommended) {
                        product.recommended_is_changing = true;
                        $scope.product_group_changing[product.product_group] = true;

                        var set_message = LOCALE.maketext("“[_1]” is now recommended.", _.escape(product.display_name));
                        var unset_message = LOCALE.maketext("“[_1]” is no longer recommended.", _.escape(product.display_name));
                        var success_message = recommended ? set_message : unset_message;
                        return editProductsService.set_provider_product_recommended(product, product.provider_name, recommended).then(function() {

                            growl.success(success_message);

                            if ( recommended ) {
                                for (var x = 0; x < $scope.products.length; x++) {
                                    if ( $scope.products[x].product_group === product.product_group ) {
                                        $scope.products[x].recommended = false;
                                    }
                                }
                            }
                            product.recommended = recommended;
                        }, growlError).finally( function() {
                            product.recommended_is_changing = false;
                            $scope.product_group_changing[product.product_group] = false;
                        } );
                    };

                    function format_dollars(value) {
                        value = parseFloat(value) + 0.001;
                        var localized_value = LOCALE.numf(value);
                        return localized_value.substr(0, localized_value.length - 1);
                    }

                    $scope.format_dollars = format_dollars;

                    // TODO: If/when we parse localized numbers, set this to use
                    // that logic. It’ll basically be the inverse of format_dollars().
                    var _parseGivenPrice = Number;

                    $scope.get_product_commission = function(product) {
                        var commission = product[product._pricing_attribute] / 3;

                        // Round to the nearest one hundredth (i.e., penny).
                        commission = Math.round(100 * commission);

                        return parseFloat(("" + commission).replace(/(..)$/, ".$1"));
                    };

                    $scope.editProductPrice = function(product, wildcard) {

                        var productDisplayName = _.escape(product.display_name);
                        var editingAttribute = product._pricing_attribute;
                        var providerCommission = $scope.provider_commission[product.provider_name];

                        var minimumPrice = product.x_price_per_domain_minimum;
                        var maximumPrice = product.x_price_per_domain_maximum;
                        var editingDescription = LOCALE.maketext("Editing the per-domain pricing for the product “[_1]”.", product.display_name);

                        if (wildcard) {
                            editingAttribute = product._wildcard_pricing_attribute;
                            minimumPrice = product.x_price_per_wildcard_domain_minimum;
                            maximumPrice = product.x_price_per_wildcard_domain_maximum;
                            editingDescription = LOCALE.maketext("Editing the per-wildcard-domain pricing for the product “[_1]”.", product.display_name);
                        }

                        var price = product[editingAttribute];

                        // Creating isolated scope for flexibility with wildcard
                        var modalScope = {
                            editingDescription: editingDescription,
                            product: {
                                providerCommissionMessage: providerCommission ? $scope.get_provider_commission_msg(providerCommission) : null,
                                settingPrice: false,
                                price: {
                                    unit: product.price_unit,
                                    minimum: minimumPrice || 0,
                                    maximum: maximumPrice || 1000000,
                                    minimumMessage: $scope.get_min_price_msg(minimumPrice),
                                    maximumMessage: $scope.get_max_price_msg(maximumPrice),
                                    multipleOf: providerCommission ? $scope.provider_commission[product.provider_name] : 0.01,
                                },
                            },


                            // Use toFixed() for now instead of format_dollars()
                            // until we can actually parse localized numbers.
                            new_price: _parseGivenPrice(price).toFixed(2),
                            cancel_change_price: cancelChangePrice,
                            set_price: setPrice,
                        };

                        function cancelChangePrice() {

                            // We only need to remove the modal now
                            modal.close();
                        }

                        function setPrice(newPrice, priceForm) {
                            modalScope.product.settingPrice = true;

                            var price = _parseGivenPrice(newPrice);
                            var editingSuccessMessage;
                            if ( wildcard ) {
                                editingSuccessMessage = LOCALE.maketext("The system has successfully set the per-wildcard-domain pricing for the product “[_1]” to $[_2].", productDisplayName, format_dollars(price));
                            } else {
                                editingSuccessMessage = LOCALE.maketext("The system has successfully set the per-domain pricing for the product “[_1]” to $[_2].", productDisplayName, format_dollars(price));
                            }

                            return editProductsService.setMarketProductAttribute(product.provider_name, product.product_id, editingAttribute, price).then(function() {
                                product[editingAttribute] = price;

                                modal.dismiss();

                                priceForm.$setPristine();
                                growl.success(editingSuccessMessage);
                            }, growlError).finally(function() {
                                modalScope.product.settingPrice = false;
                            });
                        }

                        var $isolateScope = $scope.$new();
                        angular.extend($isolateScope, modalScope);

                        // We use the template in the page to reduce any delay from using templateUrl
                        var template = document.getElementById("product-price-modal").text;
                        modal = $uibModal.open({
                            template: template,
                            scope: $isolateScope,
                            size: "sm"
                        });
                    };

                    $scope.product_orderBy_sorter = function(p) {
                        return p[p._pricing_attribute];
                    };

                    var _product_lookup = {};
                    var _metadata_lookup = {};

                    var _when_done_loading = function() {
                        $scope.$parent.loading = false;

                        // Prepare specific display attributes.
                        $scope.products.forEach( function(p) {
                            var key = p.provider_name + "/" + p.product_id;

                            p._pricing_attribute = p.x_ssl_per_domain_pricing ? "x_price_per_domain" : "price";

                            if (p.x_price_per_wildcard_domain) {
                                p._wildcard_pricing_attribute = "x_price_per_wildcard_domain";
                            }

                            try {
                                p._price_is_read_only = _metadata_lookup[key].attributes[p._pricing_attribute].read_only;
                            } catch (e) {
                                $log.warn("Missing metadata attribute?", JSON.stringify(p), key, JSON.stringify(_metadata_lookup), e);
                                p._price_is_read_only = true;
                            }
                        } );
                    };

                    $scope.get_recommended_tooltip = function(product) {
                        return (product.recommended) ?
                            LOCALE.maketext("Clear the recommended product setting for this product group.") :
                            LOCALE.maketext("Make this the recommended product for its product group.");
                    };

                    $scope.get_provider_commission_msg = function(value) {
                        return LOCALE.maketext("Enter a multiple of $[_1] USD.", format_dollars(value));
                    };

                    $scope.get_min_price_msg = function(value) {
                        return LOCALE.maketext("The minimum price is $[_1] USD.", format_dollars(value));
                    };


                    $scope.get_max_price_msg = function(value) {
                        return LOCALE.maketext("The maximum price is $[_1] USD.", format_dollars(value));
                    };

                    $scope.init = function() {
                        $scope.fetching_products = true;
                        $scope.fetching_metadata = true;
                        $scope.selected_product = undefined;
                        $scope.$parent.loading = true;

                        editProductsService.fetch_products().then(function() {}, function(error) {
                            growl.error(error);
                        }).then(function() {
                            $scope.fetching_products = false;
                            $scope.products = editProductsService.get_products();

                            $scope.products.forEach( function(p) {
                                _product_lookup[ p.provider_name + "/" + p.product_id ] = p;
                            } );

                            // Because this can occur in an orphan scope we need to verify the parent exists
                            if ($scope && $scope.$parent && !$scope.fetching_metadata) {
                                _when_done_loading();
                            }
                        });

                        editProductsService.fetch_product_metadata().then(function() {}, function(error) {
                            growl.error(error);
                        }).then(function() {
                            $scope.fetching_metadata = false;
                            $scope.product_metadata = editProductsService.get_product_metadata();

                            $scope.product_metadata.forEach( function(m) {
                                _metadata_lookup[ m.provider_name + "/" + m.product_id ] = m;
                            } );

                            if ($scope && $scope.$parent && !$scope.fetching_products) {
                                _when_done_loading();
                            }
                        });
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# templates/ssl_provider_manager/views/editCPStoreController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/editCPStoreController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/email-validator"
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "editCPStoreController", [
                "$scope",
                "editCPStoreService",
                "growl",
                function($scope, editCPStoreService, growl) {
                    function _growl_error(error) {
                        return growl.error( _.escape(error) );
                    }

                    $scope.init = function() {
                        $scope.locale = LOCALE;
                        $scope.$parent.loading = true;

                        editCPStoreService.fetch_market_providers_commission_config().then(function() {
                            $scope.cpstore_commission_config = editCPStoreService.get_market_providers_commission_config().filter( function(c) {
                                return c.provider_name === "cPStore";
                            } )[0];
                        }, _growl_error).then(function() {
                            if ($scope && $scope.$parent) {
                                $scope.$parent.loading = false;
                            }
                        });
                    };

                    $scope.set_commission_id = function(provider, commission_id) {
                        var message = LOCALE.maketext("You have set the Commission [asis,ID] for “[_1]” to “[_2]”.", _.escape(provider), _.escape(commission_id));
                        $scope.setting_commission_id = true;

                        return editCPStoreService.set_commission_id(provider, commission_id).then(function() {
                            growl.success(message);
                        }, _growl_error)
                            .then( function() {
                                $scope.setting_commission_id = false;
                            } );
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);

/*
# templates/ssl_provider_manager/index.js Copyright(c)             2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

/* global define: false, require: false */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "uiBootstrap",
        "ngRoute",
        "ngAnimate"
    ],
    function(angular, CJT) {

        "use strict";

        CJT.config.html5Mode = false;

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "ngAnimate"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/services/editProductsService",
                    "app/services/editCPStoreService",
                    "app/views/manageController",
                    "app/views/editProductsController",
                    "app/views/editCPStoreController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    // If using views
                    app.controller("BaseController", ["$rootScope", "$scope", "$route", "$location",
                        function($rootScope, $scope, $route, $location) {

                            $scope.loading = false;

                            // Convenience functions so we can track changing views for loading purposes
                            $rootScope.$on("$routeChangeStart", function() {
                                $scope.loading = true;
                            });
                            $rootScope.$on("$routeChangeSuccess", function() {
                                $scope.loading = false;
                            });
                            $rootScope.$on("$routeChangeError", function() {
                                $scope.loading = false;
                            });
                            $scope.current_route_matches = function(key) {
                                return $location.path().match(key);
                            };
                            $scope.onSelectTab = function(tabIndex) {
                                $scope.activeTabIndex = tabIndex;
                            };
                            $scope.go = function(path, tabIndex) {
                                $location.path(path);
                                $scope.active_path = path;
                                $scope.onSelectTab(tabIndex);
                            };

                            $scope.activeTabIndex = 0;
                        }
                    ]);

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup a route - copy this to add additional routes as necessary
                            $routeProvider.when("/", {
                                controller: "manageController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/manageView.ptt")
                            });

                            $routeProvider.when("/edit_products/", {
                                controller: "editProductsController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/editProducts.ptt")
                            });

                            $routeProvider.when("/edit_cpstore_config/", {
                                controller: "editCPStoreController",
                                templateUrl: CJT.buildFullPath("market_provider_manager/views/editCPStore.ptt")
                            });

                            // default route
                            $routeProvider.otherwise({
                                "redirectTo": "/"
                            });

                        }
                    ]);

                    // end of using views

                    BOOTSTRAP();

                });

            return app;
        };
    }
);

