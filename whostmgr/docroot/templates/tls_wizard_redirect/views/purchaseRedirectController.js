/*
# templates/tls_wizard_redirect/views/purchaseRedirectController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "purchaseRedirectController", [
                "$scope",
                "$filter",
                "indexService",
                "growl",
                function($scope, $filter, indexService, growl) {
                    var _growl_error = function(err) {
                        growl.error(_.escape(err));
                    };
                    var defaultTheme = indexService.get_default_theme();

                    var domains = indexService.get_domains();
                    var accounts = [];
                    var need_to_enable_provider = indexService.get_enabled_provider_count() ? false : true;
                    angular.forEach(domains, function(value, key) {
                        accounts.push( { "username": value, "domain": key } );
                    });

                    $scope.accounts = accounts;

                    $scope.meta = {

                        // sort settings
                        sortReverse: false,
                        sortBy: "username",
                        sortDirection: "desc",

                        // pager settings
                        maxPages: 5,
                        totalItems: $scope.accounts.length,
                        currentPage: 1,
                        pageSize: 10,
                        pageSizes: [10, 20, 50, 100],
                        start: 0,
                        limit: 10,

                        filterValue: "",
                    };
                    $scope.showPager = true;

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo"),
                    };

                    // update the table on sort
                    $scope.sortList = function() {
                        $scope.fetch();
                    };

                    // update table on pagination changes
                    $scope.selectPage = function() {
                        $scope.fetch();
                    };

                    // update table on page size changes
                    $scope.selectPageSize = function() {
                        $scope.fetch();
                    };

                    $scope.searchList = function() {
                        $scope.fetch();
                    };

                    var min_value_in_array = function(arr) {
                        var min_value = arr[0];
                        for (var x = 0; x < arr.length; x++) {
                            min_value = arr[x] < min_value ? arr[x] : min_value;
                        }

                        return min_value;
                    };

                    // update table
                    $scope.fetch = function() {
                        var filteredList = [];

                        // filter list based on search text
                        if ($scope.meta.filterValue !== "") {
                            filteredList = filters.filter($scope.accounts, $scope.meta.filterValue, false);
                        } else {
                            filteredList = $scope.accounts;
                        }

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        // filter list based on page size and pagination
                        if ($scope.meta.totalItems > min_value_in_array($scope.meta.pageSizes)) {
                            var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                            var limit = ( $scope.meta.pageSize > 0 ) ? $scope.meta.pageSize : $scope.meta.totalItems;

                            filteredList = filters.limitTo(filters.startFrom(filteredList, start), limit);
                            $scope.showPager = true;

                            // table statistics
                            $scope.meta.start = start + 1;
                            $scope.meta.limit = start + filteredList.length;

                        } else {

                            // hide pager and pagination
                            $scope.showPager = false;

                            if (filteredList.length === 0) {
                                $scope.meta.start = 0;
                            } else {

                                // table statistics
                                $scope.meta.start = 1;
                            }

                            $scope.meta.limit = filteredList.length;
                        }

                        $scope.filteredAccounts = filteredList;

                        return filteredList;
                    };

                    // first page load
                    $scope.fetch();

                    $scope.process_user_and_generate_login_url = function(user, domain) {

                        if (need_to_enable_provider) {

                            // Do this immediately so fast clickers don't trigger multiple updates
                            need_to_enable_provider = false;
                            return indexService.enable_cpstore_provider().then(function(success) {
                                growl.success(LOCALE.maketext("Because no other providers are enabled, the system enabled the [asis,cPanel Store] provider."));
                                return check_user_has_features_then_generate_session(user, domain);
                            }, function(error) {
                                need_to_enable_provider = true;
                                _growl_error(error);
                            });
                        } else {
                            return check_user_has_features_then_generate_session(user, domain);
                        }
                    };

                    $scope.get_pagination_msg = function() {
                        return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", $scope.meta.start, $scope.meta.limit, $scope.meta.totalItems);
                    };

                    var check_user_has_features_then_generate_session = function(user, domain) {
                        var required_features = ["market", "tls_wizard", "sslinstall"];
                        var features_to_enable = {};

                        return indexService.check_user_has_features(user, required_features).then(function(success) {
                            for (var x = 0; x < success.data.length; x++) {
                                var return_data = success.data[x].parsedResponse.data;
                                if (!return_data.has_feature) {

                                    // For every query push the feature we asked about into a store if the user doesn't have it
                                    features_to_enable[return_data.query_feature] = 1;
                                    features_to_enable["should_be_set"] = true;
                                }
                            }
                            if (features_to_enable.should_be_set) {
                                delete features_to_enable.should_be_set;
                                return indexService.force_enable_features_for_user(user, features_to_enable).then(function(success) {
                                    var features = Object.keys(features_to_enable).sort();

                                    growl.success(LOCALE.maketext("The system enabled the [numerate,_1,feature,features] [list_and_quoted,_2] for the user “[_3]” to ensure access to the “[_4]”.", features.length, features, user, LOCALE.maketext("[asis,SSL]/[asis,TLS] Wizard")));
                                    return get_user_session(user, domain);
                                }, _growl_error);
                            } else {
                                return get_user_session(user, domain);
                            }
                        }, _growl_error);
                    };

                    var get_user_session = function(user, domain) {

                        var _create_user_session = function() {
                            return indexService.create_user_session(user).then(function(success) {
                                var generated_url = success.data.url + "#/purchase-certificates/" + domain;

                                // Try to open but will most likely be blocked by browser default pop-up blocker - that's ok!
                                window.open(generated_url, "_blank");
                                growl.success(LOCALE.maketext("Click to continue as the “[_1]” user and purchase an [asis,SSL] certificate.", _.escape(user)), {
                                    ttl: -1,
                                    variables: {
                                        buttonLabel: "Purchase SSL",
                                        showAction: true,
                                        action: function() {

                                            // your callback function goes here
                                            window.open(generated_url, "_blank");
                                        },
                                    },
                                });
                            }, _growl_error);
                        };

                        return indexService.get_user_account_info(user).then(function(success) {

                            // if theme is x3 we should set the theme to retro so the redirect works properly
                            if (success.data[0].theme === "x3") {

                                // set the theme to the default theme
                                return indexService.set_user_theme_to_default_theme(user).then(function(success) {

                                    // ...and the style to retro
                                    return indexService.set_user_style_to_retro(user).then(function(success) {

                                        // if we succeed let the user know we updated the targeted users styles/theme
                                        growl.success(LOCALE.maketext("The system changed the theme for user “[_1]” to “[_2]”, with the “[asis,Retro]” style, to support this feature.", _.escape(user)), {
                                            ttl: -1,
                                        }, defaultTheme);

                                        // ...and make a call to create the user session
                                        return _create_user_session();
                                    }, function(error) {

                                        // failed to set the style but we have an updated theme, should roll back theme to x3 then give an error
                                        growl.error(LOCALE.maketext("You cannot redirect to this account because it does not have theme support for this feature."));
                                    });
                                }, function(error) {

                                    // we were unable to set the user theme to the default theme so lets let them know why we won't proceed
                                    growl.error(LOCALE.maketext("You cannot redirect to this account because it does not have theme support for this feature."));
                                });
                            } else {

                                // if they don't have x3 we assume they have support
                                return _create_user_session();
                            }
                        }, function(error) {

                            // ...if we fail to fetch user info there is probably something bad going on so lets bail out early
                            growl.error(LOCALE.maketext("The system failed to fetch the user’s account information because of the following error: [_1]", _.escape(error)));
                            return;
                        });
                    };
                },
            ]
        );

        return controller;
    }
);
