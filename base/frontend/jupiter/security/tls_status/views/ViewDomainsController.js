/*
 * base/frontend/jupiter/security/tls_status/views/ViewDomainsController.js
 *                                                    Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false, PAGE: false */
/* jshint -W100, -W104 */
/* eslint-env es6 */
/* eslint camelcase: 0 */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/query",
        "cjt/services/fuzzy",
        "uiBootstrap",
        "cjt/modules",
        "cjt/directives/cpanel/searchSettingsPanel",
        "cjt/models/searchSettingsModel",
        "app/services/DomainsService",
        "cjt/directives/actionButtonDirective",
    ],
    function(angular, CJT, LOCALE, QUERY, Fuzzy) {
        "use strict";

        var TLS_WIZ_URL = "security/tls_wizard/#/create";

        var app = angular.module("App");
        app.value("PAGE", PAGE);

        var fuzzy = new Fuzzy();

        app.controller("ViewDomainsController", [
            "$scope",
            "$timeout",
            "$filter",
            "$window",
            "$location",
            "DomainsService",
            "$routeParams",
            "SearchSettingsModel",
            "user_domains",
            "search_filter_settings",
            "alertService",
            "PAGE",
            function ViewDomainsController($scope, $timeout, $filter, $window, $location, $service, $routeParams, SearchSettingsModel, user_domains, search_filter_settings, alertService, PAGE) {

                $scope.domains = user_domains;
                $scope.filteredDomains = $scope.domains;
                $scope.selected_auto_ssl_domains = {
                    excluded: [],
                    included: [],
                };
                $scope.unsecuredDomains = [];
                $scope.quickFilterValue = "";
                $scope.showPager = true;
                $scope.autossl_enabled = $service.is_autossl_enabled;
                $scope.autoSSLErrorsExist = false;

                $scope.meta = {
                    filterValue: "",
                };

                var last_descriptor = null;

                $scope.datasource = {
                    get: function(descriptor, success) {

                        var result = $scope.filteredDomains.slice(Math.max(descriptor.index, 0), descriptor.index + descriptor.count);
                        success(result);

                        last_descriptor = descriptor;

                        last_descriptor.position = $window.pageYOffset;

                    },
                };

                // When scrolling up a lot, check number of items we are transitioning and "reload" if necessary
                $scope.check_for_reload = function() {

                    if (!last_descriptor) {
                        return;
                    }

                    var new_first_item = -1;
                    var max_loaded = last_descriptor.index + last_descriptor.count;

                    if ($window.pageYOffset === 0) {

                        // reset to zero
                        new_first_item = 0;
                    } else {

                        var position = $window.pageYOffset;
                        var perc_scrolled = last_descriptor.position / position;

                        new_first_item = max_loaded * perc_scrolled;

                    }

                    // If we are skipping more than "n" items, reload
                    if (max_loaded - new_first_item > 200) {

                        // Gotta Math.max this because: Safari
                        new_first_item = Math.max(new_first_item, 0);
                        $scope.uiScrollAdapter.reload(new_first_item);
                    }


                };

                $scope.autossl_include_domains = function(domains) {
                    var flat_domains = domains.map(function(domain) {
                        domain.updating = true;
                        return domain.domain;
                    });

                    return $service.autossl_include_domains(flat_domains).then(function() {
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("The following domains have had their [asis,AutoSSL] exclusion removed: [list_and_quoted,_1]", flat_domains),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsStatus",
                        });
                        domains.forEach(function(domain) {
                            domain.excluded_from_autossl = false;
                            domain.domain_autossl_status = "included";
                            domain.certificate_status_name = $service.get_certificate_status(domain);
                        });
                    }).finally(function() {
                        domains.forEach(function(domain) {
                            domain.updating = false;
                        });
                        $scope.update_auto_ssl_domains();
                    });
                };

                $scope.autossl_exclude_domains = function(domains) {
                    var flat_domains = domains.map(function(domain) {
                        domain.updating = true;
                        return domain.domain;
                    });

                    return $service.autossl_exclude_domains(flat_domains).then(function() {
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("The following domains will now be excluded from the [asis,AutoSSL] process: [list_and_quoted,_1]", flat_domains),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsStatus",
                        });
                        domains.forEach(function(domain) {
                            domain.excluded_from_autossl = true;
                            domain.domain_autossl_status = "excluded";
                            domain.certificate_status_name = $service.get_certificate_status(domain);
                        });
                    }).finally(function() {
                        domains.forEach(function(domain) {
                            domain.updating = false;
                        });
                        $scope.update_auto_ssl_domains();
                    });

                };

                $scope.autossl_include_domain = function(domain) {
                    return $scope.autossl_include_domains([domain]);
                };

                $scope.autossl_exclude_domain = function(domain) {
                    return $scope.autossl_exclude_domains([domain]);
                };

                $scope.exclude_autossl_label = function(domains) {
                    if (domains.length === 0) {
                        return LOCALE.maketext("Exclude Domains from AutoSSL", domains.length);
                    } else {
                        return LOCALE.maketext("Exclude [quant,_1,Domain,Domains] from AutoSSL", domains.length);
                    }
                };

                $scope.include_autossl_label = function(domains) {
                    if (domains.length === 0) {
                        return LOCALE.maketext("Include Domains during AutoSSL", domains.length);
                    } else {
                        return LOCALE.maketext("Include [quant,_1,Domain,Domains] during AutoSSL", domains.length);
                    }
                };

                $scope.searchFilterOptions = new SearchSettingsModel(search_filter_settings);

                /**
                 * Clears the search term
                 *
                 * @scope
                 * @method clearSearch
                 */
                $scope.clearSearch = function() {
                    $scope.meta.filterValue = "";
                    $scope.domainSearchFilterChanged();
                };

                $scope.filter_domains = function(domains) {

                    var filtered_domains = domains;

                    if ($scope.meta.filterValue) {

                        // using Fuzzy search here to not only search, but to utilize the ranked sorting.
                        var searchedDomains = [];
                        var domainMap = {};
                        var string_domains = domains.map(function(domain) {
                            domainMap[domain.domain] = domain;
                            return domain.domain;
                        });
                        fuzzy.loadSet(string_domains);
                        fuzzy.search($scope.meta.filterValue).filter(function(result) {
                            return result.distance < 3;
                        }).sort(function(a, b) {

                            // Re-sort using the distance AND the match
                            // So it's in alphabetical if they have the same distance
                            if (a.distance === b.distance) {
                                if (a.match === b.match) {
                                    return 0;
                                }
                                return a.match < b.match ? -1 : 1;
                            }
                            return a.distance < b.distance ? -1 : 1;
                        }).forEach(function(fuzzyMatch) {
                            searchedDomains.push(domainMap[fuzzyMatch.match]);
                        });
                        filtered_domains = searchedDomains;
                    }

                    filtered_domains = $scope.searchFilterOptions.filter(filtered_domains);

                    return filtered_domains;
                };

                $scope.update_auto_ssl_domains = function() {
                    $scope.selected_auto_ssl_domains = {
                        excluded: [],
                        included: [],
                    };

                    angular.forEach($scope.filteredDomains, function(domain) {
                        if (!domain.can_autossl_exclude) {
                            return;
                        }
                        if (domain.selected) {
                            if (domain.excluded_from_autossl) {
                                $scope.selected_auto_ssl_domains.excluded.push(domain);
                            } else {
                                $scope.selected_auto_ssl_domains.included.push(domain);
                            }
                        }
                    }, $scope.selected_auto_ssl_domains);
                };

                $scope.searchSettingsPanelUpdated = function() {
                    $scope.fetch();
                };

                $scope.lastFetch = "";

                $scope.fetch = function() {

                    var new_domains = $scope.domains;

                    new_domains = $scope.filter_domains(new_domains);

                    var newFetch = new_domains.map(function(domain) {
                        return domain.domain;
                    }).join("|");

                    // prevent some unnecessary flickering when it's showing all the domains
                    var domains_changed = $scope.filteredDomains.length !== $scope.domains.length || new_domains.length !== $scope.filteredDomains.length || $scope.lastFetch !== newFetch;
                    $scope.lastFetch = newFetch;

                    if (domains_changed) {
                        $scope.filteredDomains = new_domains;
                        if ($scope.uiScrollAdapter && angular.isFunction($scope.uiScrollAdapter.reload)) {
                            $scope.uiScrollAdapter.reload(0);
                        }
                    }

                    $scope.update_auto_ssl_domains();

                    $scope.update_showing_text();

                };

                $scope.no_results_msg = function() {
                    return LOCALE.maketext("No results found…");
                };

                $scope.get_advanced_filter_label = function(filterType) {

                    if (filterType === "displayAutoSubdomains") {
                        return $scope.advancedFilters.displayAutoSubdomains ? LOCALE.maketext("Yes") : LOCALE.maketext("No");
                    }

                    var filterOptions = $scope[filterType + "Options"];

                    if (filterOptions) {
                        for (var i = 0; i < filterOptions.length; i++) {
                            if (filterOptions[i].value === $scope.advancedFilters[filterType]) {
                                return filterOptions[i].label;
                            }
                        }
                    }

                    return "";

                };

                $scope.advanced_filters_set = function() {

                    if ($scope.advancedFilters.domainType !== "all" || $scope.advancedFilters.sslType !== "all" || $scope.advancedFilters.sslStatus !== "all" || !$scope.advancedFilters.displayAutoSubdomains) {
                        return true;
                    }

                    return false;
                };

                $scope.update_showing_text = function() {
                    $scope.showing_text = LOCALE.maketext("[output,strong,Showing] [numf,_1] of [quant,_2,domain,domains]", $scope.filteredDomains.length, $scope.domains.length);
                };

                $scope.get_showing_text = function() {
                    return $scope.showing_text;
                };

                $scope.view_certificate = function(domain) {
                    return $window.open(domain.view_crt_url);
                };

                $scope._get_tls_wizard_url = function(params) {
                    var url = TLS_WIZ_URL;

                    // same logic exists in _assets/MasterController.js
                    // exposing this as a service layer might be useful
                    if (url.search(/^http/i) === -1) {
                        if (url.search(/^\//) !== -1) {
                            url = CJT.getRootPath() + url;
                        } else {
                            url = CJT.buildFullPath(url);
                        }
                    }

                    url += "?" + QUERY.make_query_string(params);

                    return url;
                };

                // This accepts a domain object and, if the domain
                // leads with “www.”, returns the object for the
                // corresponding non-www domain. It falls back to the
                // given domain object if there is no corresponding
                // non-www domain.
                //
                $scope.get_root_domain = function(domain) {
                    var root_domain;

                    if (domain.domain.match(/^www\./)) {
                        root_domain = $scope.find_domain_by_domain(domain.domain.replace(/^www\./, ""));
                    }

                    return root_domain || domain;

                };

                $scope.upgrade_certificate_url = function(domain) {

                    if (domain) {
                        var params = {
                            domain: $scope.get_root_domain(domain).domain,
                            certificate_type: domain.available_upgrades,
                        };

                        return $scope._get_tls_wizard_url(params);
                    }
                };

                $scope.purchase_certificate = function(domains) {
                    var params = {
                        domain: domains.map(function(domain) {
                            var actual_domain = $scope.get_root_domain(domain);
                            return actual_domain.domain;
                        }),
                        certificate_type: ["dv", "ov", "ev"],
                    };

                    window.open($scope._get_tls_wizard_url(params), "_self");
                    return false;
                };

                $scope.domainSearchFilterChanged = function() {
                    if ($scope.meta.filterValue) {
                        $location.search("domain", $scope.meta.filterValue);
                    } else {
                        $location.search("domain", null);
                    }
                    $scope.fetch();
                };

                $scope.get_unsecured_domains_message = function(domains) {
                    return LOCALE.maketext("You have [numf,_1] unsecured parent [numerate,_1,domain,domains]. Would you like to purchase [numerate,_1,a certificate for that domain, certificates for those domains]?", domains.length);
                };

                $scope.getUnsecuredDomainsMessageNote = function() {
                    return PAGE.hasWebServerRole && LOCALE.maketext("[output,strong,Note:] The number of “parent” domains excludes the “[_1]” domains because the system automatically includes them during purchase if they pass [output,acronym,DCV,Domain Control Validation].", "www");
                };

                $scope.find_domain_by_domain = function(domain) {
                    for (var i = 0; i < $scope.domains.length; i++) {
                        if ($scope.domains[i].domain === domain) {
                            return $scope.domains[i];
                        }
                    }
                };

                $scope.get_domain_lock_tooltip = function(tooltip_type, is_autossl, domain_type) {

                    var validation_ranks = $service.get_validation_ranks();

                    if (validation_ranks[domain_type] > validation_ranks[tooltip_type]) {

                        // Hard coded "is_autossl" for tooltip purposes
                        return $service.get_validation_type_name(tooltip_type, false);
                    } else if (validation_ranks[domain_type] === validation_ranks[tooltip_type]) {
                        return $service.get_validation_type_name(tooltip_type, is_autossl);
                    }

                    // Hard coded "is_autossl" for tooltip purposes
                    if ($service.tls_wizard_can_do_validation_type(tooltip_type)) {
                        return LOCALE.maketext("Upgrade to [_1]", $service.get_validation_type_name(tooltip_type, false));
                    }

                    return "";
                };

                $scope.show_unsecured_domains = function() {
                    $scope.searchFilterOptions.show_only("sslType", "unsecured");
                    $scope.fetch();
                };

                $scope.get_upgrade_btn_title = function(domain) {
                    if (domain.upgrade_btn_title) {
                        return domain.upgrade_btn_title;
                    }
                    var root_domain = $scope.get_root_domain(domain);
                    domain.upgrade_btn_title = $service.get_upgrade_btn_title(root_domain.domain, domain.certificate);
                    return domain.upgrade_btn_title;
                };

                $scope.selectAllItems = function(allRowsSelected) {
                    angular.forEach($scope.filteredDomains, function(row) {
                        row.selected = allRowsSelected;
                    });
                    $scope.update_auto_ssl_domains();
                };

                $scope.getRawLogWarning = function() {
                    return LOCALE.maketext("Because some entries contain raw log data, the system may not translate it into the chosen language or locale.");
                };

                function _buildCheckCycle() {
                    var pollingInterval = 1000 * 60;
                    var messageTime = 5;
                    var messageTimeMs = messageTime * 1000;
                    $timeout(function() {

                        // Check the status of the AutoSSL check
                        $service.isAutoSSLCheckInProgress().then(function(inProgress) {

                            // If it's not in progress, notify and reload
                            if (!inProgress) {
                                $scope.autoSSLCheckActive = false;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The [asis,AutoSSL] check has completed. The page will refresh in [quant,_1,second,seconds].", messageTime),
                                    closeable: true,
                                    replace: false,
                                    autoClose: messageTimeMs,
                                    group: "tlsStatus",
                                });
                                $timeout(function() {
                                    $window.location.reload();
                                }, messageTimeMs);
                            } else {
                                _buildCheckCycle();
                            }
                        });
                    }, pollingInterval);
                }

                /**
                 * Get the label for the AutoSSL check button
                 *
                 * @method startUserAutoSSLLabel
                 *
                 * @return {String} returns the label for the current AutoSSL state
                 *
                 */
                $scope.startUserAutoSSLLabel = function() {
                    if ($scope.autoSSLCheckActive) {
                        return LOCALE.maketext("[asis,AutoSSL] is in progress …");
                    } else {
                        return LOCALE.maketext("Run [asis,AutoSSL]");
                    }
                };

                /**
                 * Start the AutoSSL run for this user
                 *
                 * @method startUserAutoSSL
                 *
                 * @return {Promise} returns promise, mostly for cpaction button to run for minutes
                 *
                 */
                $scope.startUserAutoSSL = function() {
                    $scope.autoSSLCheckActive = true;
                    $service.startUserAutoSSL().then(_buildCheckCycle);
                };


                $scope.init = function() {

                    if ($routeParams["domain"]) {
                        $scope.meta.filterValue = $routeParams["domain"];
                    }

                    angular.element($window).bind("scroll", $scope.check_for_reload);

                    var all_unsecured_domains = [];

                    $scope.domains.forEach(function(domain) {
                        domain.upgrade_btn_title = $scope.get_upgrade_btn_title(domain);
                        if (domain.certificate_type === "unsecured") {
                            all_unsecured_domains.push(domain);
                        }
                    });

                    var unsecuredActuals = [];
                    var uniqueDomains = {};

                    angular.forEach(all_unsecured_domains, function(domain) {

                        // Do not include DDNS subdomains
                        if (domain.isDDNS) {
                            return;
                        }

                        var actual_domain = $scope.get_root_domain(domain);

                        if (actual_domain.certificate_type !== "unsecured") {
                            return false;
                        }

                        if (actual_domain && !uniqueDomains[actual_domain.domain]) {
                            uniqueDomains[actual_domain.domain] = actual_domain;
                            unsecuredActuals.push(actual_domain);
                        }

                    });

                    $scope.market_products_available = $service.areMarketProductsAvailable();

                    $scope.unsecuredDomains = unsecuredActuals;

                    $scope.fetch();

                    if ( $service.is_autossl_enabled() ) {
                        $timeout(function() {

                            // Load AutoSSL Logs
                            $service.getAutoSSLStatuses().then(function(statuses) {

                                statuses.forEach(function(status) {

                                    var domainObj = $scope.find_domain_by_domain(status.domain);

                                    if (!domainObj) {
                                        return;
                                    }

                                    domainObj.autoSSLStatus = status;
                                    if (status.error) {
                                        $scope.autoSSLErrorsExist = true;
                                        domainObj.certificate_status = "has_autossl_problem";
                                        domainObj.autoSSLStatus.lastRunMessage = LOCALE.maketext("An error occurred the last time [asis,AutoSSL] ran, on [local_datetime,_1]:", domainObj.autoSSLStatus.runTime.getTime() / 1000);
                                    } else {
                                        domainObj.autoSSLStatus.lastRunMessage = LOCALE.maketext("[asis,AutoSSL] last ran on [local_datetime,_1].", domainObj.autoSSLStatus.runTime.getTime() / 1000);
                                    }

                                });

                                // Necessary because expired >> has_autossl_problem will continue to show if filtered as such until this is refreshed
                                $scope.fetch();
                            });

                            $service.isAutoSSLCheckInProgress().then(function(inProgress) {
                                $scope.initialAutoSSLCheckComplete = true;
                                $scope.autoSSLCheckActive = inProgress;
                                if ($scope.autoSSLCheckActive) {
                                    _buildCheckCycle();
                                }
                            });

                        }, 50);
                    }
                };

                $scope.$on("$destroy", function() {
                    angular.element($window).unbind("scroll", $scope.check_for_reload);
                });

                $scope.init();

            },
        ]);


    });
