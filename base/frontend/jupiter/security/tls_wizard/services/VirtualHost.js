/*
* base/frontend/jupiter/security/tls_wizard/services/VirtualHost.js
*                                                 Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


/* global define: false */
/* jshint -W100 */
/* eslint-disable camelcase */

define(
    [
        "angular",
        "lodash",
        "app/services/HasIdVerMix",
    ],
    function(angular, _, HasIdVerMix) {
        "use strict";

        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        app.factory("VirtualHost", [
            "HasIdVerMix",
            function(HasIdVerMix) {
                function VirtualHost(vhost_obj) {
                    var self = this;
                    self.display_name = "";
                    self.domains = [];
                    self.selected_domains = [];
                    self.filtered_domains = {};
                    self.show_wildcards = true;
                    self.show_domains = true;
                    self.display_meta = {
                        items_per_page: 10,
                        current_page: 1,
                    };
                    self.displayed_domains = [];
                    self.selected_product = null;
                    self.calculated_price = null;
                    self.is_ssl = 0;
                    self.product_price = 0;
                    self.product_wildcard_price = 0;
                    self.added_to_cart = false;
                    self.current_step = "domains";

                    angular.extend(self, vhost_obj);
                }

                angular.extend( VirtualHost.prototype, HasIdVerMix );

                angular.extend( VirtualHost.prototype, {
                    get_display_name: function() {
                        return this.display_name;
                    },

                    reset: function() {
                        this.current_step = "domains";
                        this.set_product(null);
                        this.set_product_price(0);
                        this.calculated_price = null;
                        this.selected_product = null;
                        angular.forEach(this.domains, function(domain) {
                            domain.selected = false;
                        });
                        this.get_selected_domains();
                    },

                    get_step: function() {
                        return this.current_step;
                    },
                    go_step: function(new_step) {
                        this.current_step = new_step;
                        return this.current_step;
                    },
                    get_price: function() {
                        var selected_domains = this.get_selected_domains();
                        var wildcard_domains = selected_domains.filter(function(domain) {
                            if (domain.is_wildcard) {
                                return true;
                            }
                            return false;
                        });
                        this.calculated_price = (this.product_price * (selected_domains.length - wildcard_domains.length)) + (wildcard_domains.length * this.product_wildcard_price);
                        return this.calculated_price;
                    },
                    set_product_price: function(price, wildcard_price) {
                        this.product_price = price || 0;
                        this.product_wildcard_price = wildcard_price || 0;
                    },
                    get_price_string: function() {
                        return "$" + this.get_price().toFixed(2) + " USD";
                    },

                    get_product: function() {
                        return this.selected_product;
                    },
                    set_product: function(product_obj) {
                        this.selected_product = product_obj;
                    },

                    get_domains: function() {
                        return this.domains;
                    },

                    set_displayed_domains: function(domains) {
                        this.displayed_domains = domains;
                    },

                    get_filtered_domains: function() {
                        var domains = this.get_domains();
                        var key;

                        if (this.show_wildcards && this.show_domains) {
                            key = "all";
                        } else if (this.show_wildcards) {
                            key = "wildcards";
                        } else if (this.show_domains) {
                            key = "domains";
                        } else {
                            return [];
                        }

                        if (this.filtered_domains[key]) {
                            return this.filtered_domains[key];
                        }

                        this.filtered_domains[key] = [];

                        var self = this;

                        angular.forEach(domains, function(domain) {
                            if (!self.show_wildcards && domain.is_wildcard) {
                                return false;
                            }
                            if (!self.show_domains && !domain.is_wildcard) {
                                return false;
                            }
                            self.filtered_domains[key].push(domain);
                        });

                        return this.filtered_domains[key];
                    },

                    get_domain_count: function(include_wildcards) {
                        if (include_wildcards) {
                            return this.domains.length;
                        }
                        return this.domains.length / 2;
                    },

                    get_displayed_domains: function() {
                        this.displayed_domains = [];

                        var filtered_domains = this.get_filtered_domains();

                        this.display_meta.start = this.display_meta.items_per_page * (this.display_meta.current_page - 1);
                        this.display_meta.limit = Math.min(filtered_domains.length, this.display_meta.start + this.display_meta.items_per_page);
                        for (var i = this.display_meta.start; i < this.display_meta.limit; i++) {

                            /* don't display wildcards*/
                            /* function is only used in 'advanced' mode */
                            if (filtered_domains[i].is_wildcard) {
                                continue;
                            }
                            this.displayed_domains.push(filtered_domains[i]);
                        }
                        return this.displayed_domains;
                    },

                    add_domain: function(domain) {
                        if (this.get_domain_by_domain(domain.domain)) {
                            return;
                        }
                        domain.resolved = -1; // Tri-state check (-1 = unchecked, 0/false = doesn't resolve, 1/true = resolves locally)
                        domain.resolving = false; // While a resolve is occuring.
                        var domain_id = this.domains.length;
                        this.domains.push(domain);
                        return domain_id;
                    },
                    get_domain_by_domain: function(domain) {
                        var match;
                        angular.forEach(this.domains, function(value) {
                            if (value.domain === domain) {
                                match = value;
                            }
                        });
                        return match;
                    },

                    // This doesn't actually remove a domain, it deselects it
                    remove_domain: function(domain) {
                        domain.selected = 0;
                        this.get_selected_domains();
                    },

                    // This doesn't actually remove domains, it deselects them
                    remove_all_domains: function() {
                        for (var i = 0; i < this.domains.length; i++) {
                            this.remove_domain(this.domains[i]);
                        }
                    },

                    is_ready: function() {
                        if (this.get_domains().length === 0) {
                            return false;
                        }
                        if (!this.get_product()) {
                            return false;
                        }
                        return true;
                    },

                    toJSON: function() {
                        var temp_data = {};
                        temp_data.display_name = this.display_name;
                        temp_data.selected_domains = this.selected_domains;
                        temp_data.selected_product = this.selected_product;
                        temp_data.calculated_price = this.calculated_price;
                        temp_data.product_price = this.product_price;
                        temp_data.domains = this.get_domains();
                        temp_data.identity_verification = this.get_identity_verification();

                        return temp_data;
                    },

                    get_selected_domains: function get_selected_domains() {
                        var selected_domains = _.filter( this.get_domains(), "selected" );
                        this.selected_domains = selected_domains;
                        return selected_domains;
                    },
                    has_selected_domains: function get_selected_domains() {
                        return _.some( this.get_domains(), "selected" );
                    },
                } );

                return VirtualHost;
            },
        ] );
    }
);
