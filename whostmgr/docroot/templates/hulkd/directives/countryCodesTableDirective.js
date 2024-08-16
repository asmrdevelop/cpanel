/*
# templates/hulkd/directives/countryCodesTableDirective
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "uiBootstrap",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/quickFiltersDirective",
    ], function(angular, _, CJT) {
        "use strict";

        var app = angular.module("App");

        app.directive("countryCodesTable", ["COUNTRY_CONSTANTS", "$timeout", function(COUNTRY_CONSTANTS, $timeout) {

            var TEMPLATE_PATH = "directives/countryCodesTable.ptt";
            var RELATIVE_PATH = "templates/hulkd/" + TEMPLATE_PATH;

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                restrict: "EA",
                scope: {
                    "items": "=",
                    "onChange": "&onChange",
                },
                replace: true,
                controller: ["$scope", "$filter", "$uibModal", function($scope, $filter, $uibModal) {

                    // confirm blacklist modal
                    $scope.modal_instance = null;
                    $scope.country_blacklist_in_progress = false;

                    $scope.confirm_country_blacklisting = function() {
                        $scope.country_blacklist_in_progress = true;

                        $scope.modal_instance = $uibModal.open({
                            templateUrl: "confirm_country_blacklisting.html",
                            scope: $scope,
                        });
                        return true;
                    };

                    $scope.cancel_country_blacklisting = function() {
                        $scope.clear_modal_instance();
                        $scope.deselectAll();
                        $scope.country_blacklisting_in_progress = false;
                    };

                    $scope.continue_country_blacklisting = function(selectedItems) {
                        $scope.clear_modal_instance();
                        $scope.country_blacklist_in_progress = false;
                        $scope.blacklistCountries(selectedItems);
                    };

                    $scope.clear_modal_instance = function() {
                        if ($scope.modal_instance) {
                            $scope.modal_instance.close();
                            $scope.modal_instance = null;
                        }
                    };

                    // initialize filter list
                    var updateTimeout;
                    $scope.filteredList = $scope.items;
                    $scope.COUNTRY_CONSTANTS = COUNTRY_CONSTANTS;
                    var countriesMap = {};

                    $scope.items.forEach(function(item) {
                        countriesMap[item.code] = item;
                        item.searchableCode = "(" + item.code + ")";
                    });

                    $scope.loading = false;

                    $scope.meta = {
                        filterValue: "",
                        sortBy: "name",
                        quickFilterValue: "all",
                    };

                    /**
                 * Initialize the variables required for
                 * row selections in the table.
                */

                    // This updates the selected tracker in the 'Selected' Badge.
                    $scope.selectedItems = [];

                    $scope.toggleSelect = function(itemCode, list) {

                        var idx = list.indexOf(itemCode);
                        if (idx > -1) {
                            list.splice(idx, 1);
                        } else {
                            list.push(itemCode);
                        }
                    };

                    $scope.toggleSelectAll = function() {
                        if ($scope.allSelected()) {
                            $scope.deselectAll();
                        } else {
                            $scope.selectAll();
                        }
                    };

                    $scope.selectAll = function() {
                        $scope.selectedItems = $scope.filteredList.map(function(item) {
                            return item.code;
                        });
                    };

                    $scope.deselectAll = function() {
                        $scope.selectedItems = [];
                    };

                    $scope.allSelected = function() {
                        return $scope.selectedItems.length && $scope.selectedItems.length === $scope.filteredList.length;
                    };

                    $scope.exists = function(item, list) {
                        return list.indexOf(item) > -1;
                    };

                    // update the table on sort
                    $scope.sortList = function(meta) {
                        $scope.fetch();
                    };

                    // update table on search
                    $scope.searchList = function(searchString) {
                        $scope.fetch();
                    };

                    $scope.getCountriesFromCodes = function(countryCodes) {
                        return countryCodes.map(function(countryCode) {
                            return countriesMap[countryCode];
                        });
                    };

                    $scope.whitelistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.WHITELISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.blacklistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.BLACKLISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.unlistCountries = function(countries) {
                        $scope.getCountriesFromCodes(countries).forEach(function(country) {
                            country.status = COUNTRY_CONSTANTS.UNLISTED;
                        });
                        $scope.countriesUpdated();
                    };

                    $scope.countriesUpdated = function() {
                        if ($scope.onChange) {

                            if (updateTimeout) {
                                $timeout.cancel(updateTimeout);
                                updateTimeout = false;
                            }

                            updateTimeout = $timeout(function() {
                                $scope.countriesUpdating = true;
                                var whitelistedDomains = [];
                                var blacklistedDomains = [];
                                $scope.items.forEach(function(item) {
                                    if (item.status === COUNTRY_CONSTANTS.WHITELISTED) {
                                        whitelistedDomains.push(item.code);
                                    } else if (item.status === COUNTRY_CONSTANTS.BLACKLISTED) {
                                        blacklistedDomains.push(item.code);
                                    }
                                });
                                $scope.onChange({ whitelist: whitelistedDomains, blacklist: blacklistedDomains }).finally(function() {
                                    $scope.countriesUpdating = false;
                                });
                            }, 250);

                        }
                    };

                    // have your filters all in one place - easy to use
                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                    };

                    $scope.quickFilterUpdated = function() {
                        $scope.deselectAll();
                        $scope.fetch();
                    };

                    // update table
                    $scope.fetch = function() {
                        var filteredList = [];

                        // filter list based on search text
                        if ($scope.meta.filterValue !== "") {
                            filteredList = filters.filter($scope.items, $scope.meta.filterValue, false);
                        } else {
                            filteredList = $scope.items;
                        }

                        if ($scope.meta.quickFilterValue !== "all") {
                            filteredList = filters.filter(filteredList, { status: $scope.meta.quickFilterValue }, false);
                        }

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        $scope.filteredList = filteredList;

                        return filteredList;
                    };

                    // first page load
                    $scope.fetch();
                }],
            };
        }]);
    });
