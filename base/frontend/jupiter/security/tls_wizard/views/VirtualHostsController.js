/*
 * base/frontend/jupiter/security/tls_wizard/views/VirtualHostsController.js
 *                                                    Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* jshint -W100 */
/* eslint-disable camelcase */

// Then load the application dependencies
define(
    [
        "angular",
        "cjt/util/locale",
        "jquery",
        "cjt/modules",
        "ngSanitize",
        "app/services/CertificatesService",
        "app/services/IdVerDefaults",
        "cjt/filters/qaSafeIDFilter",
        "cjt/directives/cpanel/searchSettingsPanel",
        "cjt/directives/triStateCheckbox",
        "cjt/directives/spinnerDirective",
        "cjt/decorators/growlDecorator",
        "app/services/CountriesService",
        "app/services/LocationService",
    ],
    function(angular, LOCALE, $) {
        "use strict";

        var app = angular.module("App");

        function VirtualHostsController(
            $rootScope,
            $scope,
            $controller,
            $location,
            $filter,
            $timeout,
            $sce,
            $routeParams,
            $window,
            CertificatesService,
            IdVerDefaults,
            SpinnerAPI,
            growl,
            COUNTRIES,
            LocationService,
            SearchSettingsModel,
            alertService) {

            $scope.show_introduction_block = CertificatesService.show_introduction_block;

            $scope.domains = CertificatesService.get_all_domains();
            $scope.virtual_hosts = CertificatesService.get_virtual_hosts();
            $scope.pending_certificates = CertificatesService.get_pending_certificates();
            $scope.showExistingCertificates = false;
            $scope.working_virtual_host = null;
            $scope.LOCALE = LOCALE;
            $scope.resolution_timeout = 0;
            $scope.cart_items = [];
            $scope.filterValue = null;
            $scope.checkout_mode = false;
            $scope.filteredProducts = [];
            $scope.showAdvancedSettings = true;
            $rootScope.addToCartGrowl = null;

            $scope.COUNTRIES = COUNTRIES;

            var identityVerification = {};
            $scope.identity_verification = identityVerification;

            var savedIDVer = CertificatesService.get_stored_extra_settings().advanced_identity_verification;

            for (var vh = 0; vh < $scope.virtual_hosts.length; vh++) {
                var vHostName = $scope.virtual_hosts[vh].get_display_name();

                identityVerification[vHostName] = {};

                if (savedIDVer && savedIDVer[vHostName]) {
                    IdVerDefaults.restore_previous(identityVerification[vHostName], savedIDVer[vHostName]);
                } else {
                    IdVerDefaults.set_defaults(identityVerification[vHostName]);
                }
            }

            // reset on visit to purchase certs
            angular.forEach($scope.virtual_hosts, function(virtualHost) {
                virtualHost.reset();

                /* don't show wildcards in this interface */
                virtualHost.show_wildcards = false;
            });

            /* to reset after reset */
            $scope.domains = CertificatesService.get_all_domains();
            $scope.domains = $filter("filter")($scope.domains, {
                is_wildcard: false,
            });
            $scope.virtual_hosts = CertificatesService.get_virtual_hosts();

            $scope.virtual_hosts = $filter("filter")($scope.virtual_hosts, function(vhost) {
                return !vhost.display_name.match(/^\*\./);
            });

            var defaultSearchValues = {
                "certTerms": {
                    "1_year": true,
                    "2_year": false,
                    "3_year": false,
                },
            };

            $scope.searchFilterOptions = new SearchSettingsModel(CertificatesService.get_product_search_options(), defaultSearchValues);

            $scope.filter_products = function() {

                var filteredProducts = CertificatesService.get_products();

                filteredProducts = $scope.searchFilterOptions.filter(filteredProducts);

                $scope.filteredProducts = filteredProducts;
            };

            $scope.slow_scroll_to_top = function() {
                $("body,html").animate({
                    "scrollTop": 0,
                }, 2000);
            };

            $scope.go_to_product_filters = function() {
                $scope.showAdvancedSettings = true;
                $scope.slow_scroll_to_top();
            };

            var buildSteps = ["domains", "providers", "cert-info"];
            var qaFilter = $filter("qaSafeID");

            $scope.get_cart_certs_title = function() {
                return LOCALE.maketext("[quant,_1,Certificate,Certificates]", $scope.get_cart_items().length);
            };

            $scope.get_vhost_showing_text = function() {
                var vhosts = $filter("filter")($scope.get_virtual_hosts(), $scope.filterValue);
                return LOCALE.maketext("[output,strong,Showing] [numf,_1] of [quant,_2,website,websites]", vhosts.length, $scope.get_virtual_hosts().length);
            };

            $scope.get_domains_showing_text = function(virtualHost) {
                var numStart = 1 + virtualHost.display_meta.start;
                var numLimit = virtualHost.display_meta.limit;
                var numOf = virtualHost.get_domain_count(true);
                return LOCALE.maketext("[output,strong,Showing] [numf,_1] - [numf,_2] of [quant,_3,domain,domains].", numStart, numLimit, numOf);
            };

            $scope.deselect_unresolved_msg = function(virtualHost) {
                var unresolvedCount = virtualHost.get_selected_domains().filter(function(domain) {
                    return domain.resolved === 0;
                }).length;
                return LOCALE.maketext("Deselect all unresolved domains ([numf,_1]).", unresolvedCount);
            };

            $scope.go_to_pending = function(orderItemID) {
                if (orderItemID) {
                    $location.path("/pending-certificates/").search("orderItemID", orderItemID);
                } else {
                    $location.path("/pending-certificates");
                }
            };

            $scope.pending_certificate = function(virtualHost) {
                var result = false;
                angular.forEach($scope.pending_certificates, function(pcert) {
                    angular.forEach(pcert.vhost_names, function(vhostName) {
                        if (vhostName === virtualHost.display_name) {
                            result = pcert.order_item_id;
                        }
                    });
                });
                return result;
            };

            $scope.get_certpanel_class = function(virtualHost) {
                if (!$scope.pending_certificate(virtualHost)) {
                    return "panel-primary";
                } else {
                    return "panel-default";
                }
            };

            $scope.view_pending_certificate = function(virtualHost) {
                var orderItemID = $scope.pending_certificate(virtualHost);
                $scope.go_to_pending(orderItemID);
            };

            $scope.get_currency_string = function(num, priceUnit) {
                num += 0.001;
                var str = LOCALE.numf(num);
                str = "$" + str.substring(0, str.length - 1);
                if (priceUnit) {
                    str += " " + priceUnit;
                }
                return str;
            };

            $scope.get_virtual_hosts = function() {
                var virtualHosts = $scope.virtual_hosts;
                if ($scope.filterValue) {
                    virtualHosts = $filter("filter")(virtualHosts, $scope.filterValue);
                }
                if ($scope.checkout_mode) {
                    virtualHosts = $filter("filter")(virtualHosts, {
                        added_to_cart: true,
                    });
                }
                return virtualHosts;
            };

            $scope.get_virtual_host_classes = function(virtualHost) {
                return {
                    "col-lg-4": $scope.virtual_hosts.length > 2,
                    "col-lg-6": $scope.virtual_hosts.length <= 2,
                    "panel-success": virtualHost.is_ssl,
                };
            };

            $scope.get_step_panel_classes = function(virtualHost, current) {
                var classes = ["col-sm-12", "col-xs-12"];

                // add step type specific classes

                if ($scope.working_virtual_host === virtualHost.display_name) {
                    classes.push("col-md-4");
                    classes.push("col-lg-4");
                } else {
                    classes.push("col-md-12");
                    classes.push("col-lg-12");
                }

                if (current) {
                    classes.push("cert-step-panel-current");
                }

                return classes;

            };

            $scope.get_cart_price = function() {
                var price = 0;
                angular.forEach($scope.get_cart_items(), function(virtualHost) {
                    price += virtualHost.get_price();
                });
                return price;
            };

            $scope.get_cart_items = function() {
                $scope.cart_items = $filter("filter")($scope.virtual_hosts, {
                    added_to_cart: true,
                });
                return $scope.cart_items;
            };

            $scope.checkout = function() {
                $scope.checkout_mode = true;
            };

            $scope.get_product_form_fields = function() {
                return [];
            };

            $scope.get_step = function(virtualHost) {
                return virtualHost.get_step();
            };

            $scope.go_step = function(virtualHost, step) {
                if ($scope.can_step(virtualHost, step)) {
                    return virtualHost.go_step(step);
                }
            };

            $scope.focus_virtual_host = function() {

                // $scope.working_virtual_host = virtual_host.display_name;
            };

            $scope.check_selected_domains = function(virtualHost) {
                if ($scope.resolution_timeout) {
                    $timeout.cancel($scope.resolution_timeout);
                }
                if (virtualHost && virtualHost.added_to_cart) {
                    var domains = $filter("filter")(virtualHost.get_selected_domains(), function(domain) {
                        if (domain.resolved !== 1) {
                            return true;
                        }
                    });
                    if (domains.length) {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("You have altered an item in your cart. The system has removed that item. After you make the necessary changes, add that item back to your cart."),
                            group: "tlsWizard",
                        });
                        $scope.remove_from_cart(virtualHost);
                    }
                }
                $scope.resolution_timeout = $timeout(function(domains) {
                    $scope.ensure_dns(domains);
                }, 850, true, CertificatesService.get_all_selected_domains()); // JNK: Lowered wait time since I keep missing it when testing
            };

            $scope.deselect_domains = function(domains) {
                angular.forEach(domains, function(domain) {
                    domain.selected = false;
                });
            };

            $scope.get_current_or_default_provider = function() {
                return CertificatesService.get_default_provider_name();
            };

            $scope.ensure_dns = function(domains) {
                domains = $filter("filter")(domains, {
                    selected: true,
                    resolved: -1,
                });
                if (!domains.length) {
                    return false;
                }
                angular.forEach(domains, function(domain) {
                    domain.resolving = true;
                    SpinnerAPI.start($scope.get_spinner_id(domain.domain));
                });
                var providerName = $scope.get_current_or_default_provider();
                return CertificatesService.ensure_domains_can_pass_dcv(domains, providerName).finally(function() {
                    var toFocusElement;
                    angular.forEach(domains, function(domain) {
                        if (domain.resolved === 0 && domain.selected) {

                            /* checked domain doesn't resolve */
                            var vhostIndex = CertificatesService.get_virtual_host_by_display_name(domain.vhost_name);
                            var vhost = $scope.virtual_hosts[vhostIndex];
                            if (vhost && vhost.get_step() === "providers") {

                                /* if we are on the providers section, send them back to the domains section to see errors */
                                $scope.go_step(vhost, "domains");

                                /* set focus to top domain in domains list */
                                var element = $window.document.getElementById($scope.get_domain_id(domain));
                                if (element && !toFocusElement) {

                                    /* only focus first element */
                                    toFocusElement = element;
                                    $timeout(function() {
                                        toFocusElement.focus();
                                    });
                                }
                            }
                        }
                        SpinnerAPI.stop($scope.get_spinner_id(domain.domain));
                    });
                });
            };

            $scope.get_domain_id = function(domainObject) {
                return qaFilter(domainObject.vhost_name + "_" + domainObject.domain);
            };

            $scope.check_product_match = function(productA, productB) {
                if (!productA || !productB) {
                    return false;
                }
                if (productA.id === productB.id && productA.provider === productB.provider) {
                    return true;
                }
            };

            $scope.can_step = function(virtualHost, step) {
                if (step === buildSteps[0]) {
                    return true;
                } else if (step === buildSteps[1]) {

                    // providers
                    /* can progress if domains are selected, after they are resolved they user is kicked back to domains if there is an error */
                    return virtualHost.get_selected_domains().length ? true : false;
                } else if (step === buildSteps[2]) {

                    // cert-info
                    var product = virtualHost.get_product();
                    if (!product) {
                        return false;
                    }
                    product = CertificatesService.get_product_by_id(product.provider, product.id);
                    if (!product) {
                        return false;
                    }
                    if (!$scope.get_product_form_fields(product)) {
                        return false;
                    }
                }
                return false;
            };

            $scope.get_product_by_id = function(providerName, productID) {
                return CertificatesService.get_product_by_id(providerName, productID);
            };

            $scope.can_next_step = function(virtualHost) {
                var currentStep = virtualHost.get_step();
                var nextStep;
                angular.forEach(buildSteps, function(step, index) {
                    if (step === currentStep) {
                        nextStep = buildSteps[index + 1];
                    }
                });

                return $scope.can_step(virtualHost, nextStep);

            };

            $scope.next_step = function(virtualHost) {
                var currentStep = virtualHost.get_step();
                var nextStep;
                angular.forEach(buildSteps, function(step, index) {
                    if (step === currentStep) {
                        nextStep = buildSteps[index + 1];
                    }
                });

                if ($scope.can_step(virtualHost, nextStep)) {
                    $scope.focus_virtual_host(virtualHost);
                    virtualHost.go_step(nextStep);
                }
            };

            $scope.get_spinner_id = function(domain) {
                return qaFilter("dns_resolving_" + domain);
            };

            $scope.get_products = function(virtualHost) {
                return $scope.filteredProducts;
            };

            $scope.set_product = function(virtualHost, product) {
                virtualHost.set_product_price(product.price);
                virtualHost.set_product(product);
            };

            $scope.all_domains_resolved = function(virtualHost) {
                var domains = virtualHost.get_selected_domains();

                domains = $filter("filter")(domains, function(domain) {
                    if (domain.resolved !== 1) {
                        return false;
                    }
                    return true;
                });

                if (domains.length === 0) {

                    // No Resolved and Selected Domains
                    return false;
                }

                return true;
            };

            $scope.can_add_to_cart = function(virtualHost) {
                var product = virtualHost.get_product();
                if (!product) {
                    return false;
                }
                product = CertificatesService.get_product_by_id(product.provider, product.id);
                if (!product) {

                    // No Valid Product Selected
                    return false;
                }

                return true;

            };

            $scope.add_to_cart = function(virtualHost) {
                if (!$scope.can_add_to_cart(virtualHost) || !$scope.all_domains_resolved(virtualHost)) {
                    return false;
                }
                virtualHost.added_to_cart = true;
                virtualHost.go_step("added-to-cart");

                virtualHost.set_identity_verification($scope.identity_verification[virtualHost.display_name]);

                $scope.working_virtual_host = null;

                // REFACTOR:: Should find a way to do this with CJT2/alertService and remove
                // growl usage here.
                if ($rootScope.addToCartGrowl) {
                    $rootScope.addToCartGrowl.ttl = 0;
                    $rootScope.addToCartGrowl = null;
                }
                var options = {
                    ttl: -1,
                    variables: {
                        buttonLabel: LOCALE.maketext("Proceed to checkout."),
                        showAction: true,
                        action: function() {
                            $scope.purchase();
                        },
                    },
                };
                $rootScope.addToCartGrowl = growl.success(LOCALE.maketext("Item Successfully Added to Cart."), options);
            };

            $scope.get_domain_certificate = function(domain) {
                return CertificatesService.get_domain_certificate(domain);
            };

            $scope.view_existing_certificate = function() {

            };

            $scope.get_virtual_host_certificate = function(virtualHost) {
                return CertificatesService.get_virtual_host_certificate(virtualHost);
            };

            $scope.build_csr_url = function(virtualHost) {
                var ihost = $scope.get_virtual_host_certificate(virtualHost);
                if (ihost && ihost.certificate) {
                    var url = "";
                    url += "../../ssl/install.html?id=";
                    url += encodeURIComponent(ihost.certificate.id);
                    return url;
                }
            };

            $scope.get_existing_certificate_name = function(virtualHost) {
                var ihost = $scope.get_virtual_host_certificate(virtualHost);

                var name;
                if (ihost && ihost.certificate) {
                    var cert = ihost.certificate;
                    if (cert.validation_type === "dv") {
                        name = LOCALE.maketext("A [output,abbr,DV,Domain Validated] certificate is installed.");
                    } else if (cert.validation_type === "ov") {
                        name = LOCALE.maketext("An [output,abbr,OV,Organization Validated] certificate is installed.");
                    } else if (cert.validation_type === "ev") {
                        name = LOCALE.maketext("An [output,abbr,EV,Extended Validation] certificate is installed.");
                    } else if (cert.is_self_signed) {
                        name = LOCALE.maketext("A self-signed certificate is installed.");
                    }
                }
                if (!name) {
                    name = LOCALE.maketext("A certificate of unknown type is installed.");
                }

                return name;
            };

            $scope.get_domain_lock_classes = function(virtualHost) {
                var ihost = $scope.get_virtual_host_certificate(virtualHost);
                if (ihost && ihost.certificate) {
                    if (ihost.certificate.is_self_signed) {
                        return "grey-padlock";
                    } else {
                        return "green-padlock";
                    }
                }
            };

            $scope.remove_from_cart = function(virtualHost) {
                if ($rootScope.addToCartGrowl) {
                    $rootScope.addToCartGrowl.ttl = 0;
                    $rootScope.addToCartGrowl.destroy();
                    $rootScope.addToCartGrowl = null;
                }
                virtualHost.added_to_cart = false;
            };

            $scope.go_to_simple = function() {
                CertificatesService.hard_reset();
                LocationService.go_to_simple_create_route().search("");
            };

            $scope.purchase = function() {

                /* storing on and removing from rootscope due to scope change */
                if ($rootScope.addToCartGrowl) {
                    $rootScope.addToCartGrowl.ttl = 0;
                    $rootScope.addToCartGrowl.destroy();
                    $rootScope.addToCartGrowl = null;
                }

                var success = CertificatesService.save({
                    advanced_identity_verification: identityVerification,
                });

                if (!success) {
                    alertService.add({
                        type: "danger",
                        message: LOCALE.maketext("Failed to save information to browser cache."),
                        group: "tlsWizard",
                    });
                } else {
                    $location.path("/purchase");
                }

            };

            if ($routeParams["domain"]) {
                angular.forEach($filter("filter")($scope.domains, {
                    domain: $routeParams["domain"],
                }, true), function(domain) {
                    domain.selected = true;
                    $scope.check_selected_domains(domain.vhost_name);
                });

                /* refresh virtual_hosts */
                $scope.virtual_hosts = CertificatesService.get_virtual_hosts();
                $scope.filterValue = $routeParams["domain"];
            }

        }

        app.controller("VirtualHostsController",
            [
                "$rootScope",
                "$scope",
                "$controller",
                "$location",
                "$filter",
                "$timeout",
                "$sce",
                "$routeParams",
                "$window",
                "CertificatesService",
                "IdVerDefaults",
                "spinnerAPI",
                "growl",
                "CountriesService",
                "LocationService",
                "SearchSettingsModel",
                "alertService",
                VirtualHostsController,
            ]);


    });
