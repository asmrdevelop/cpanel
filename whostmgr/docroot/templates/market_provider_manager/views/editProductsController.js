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
    [
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
