/*
# templates/external_auth/views/ProvidersController.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "ngSanitize",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "app/services/ProvidersService",
    ],
    function(angular, _, LOCALE) {

        var app = angular.module("App");

        function ProviderController($scope, $filter, $location, ProvidersService, PAGE) {

            $scope.providers = [];

            // meta information
            $scope.meta = {

                // sort settings
                sortReverse: false,
                sortBy: "label",
                sortDirection: "asc",

                // pager settings
                maxPages: 5,
                totalItems: $scope.providers.length,
                currentPage: 1,
                pageSize: 20,
                pageSizes: [20, 50, 100, 500],
                start: 0,
                limit: 10,

                filterValue: "",
            };

            // initialize filter list
            $scope.filteredList = $scope.providers;
            $scope.showPager = true;

            $scope.get_service_column_label = function(service) {
                return LOCALE.maketext("Status ([_1])", service);
            };

            $scope.allowed_authentication_services = PAGE.allowed_authentication_services;

            /**
             * Initialize the variables required for
             * row selections in the table.
             */
            $scope.checkdropdownOpen = false;

            // This updates the selected tracker in the 'Selected' Badge.
            $scope.totalSelectedProviders = 0;
            var selectedProviderList = [];

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

            // Select all providers on a page.
            $scope.selectAllProviders = function() {
                if ($scope.allRowsSelected) {
                    $scope.filteredList.forEach(function(item) {
                        item.rowSelected = true;

                        if (selectedProviderList.indexOf(item.id) !== -1) {
                            return;
                        }

                        selectedProviderList.push(item.id);
                    });
                } else {

                    // Extract the unselected items and remove them from the selected collection.
                    var unselectedList = $scope.filteredList.map(function(item) {
                        item.rowSelected = false;
                        return item.id;
                    });

                    selectedProviderList = _.difference(selectedProviderList, unselectedList);
                }

                // Update the selected count tracker.
                $scope.totalSelectedProviders = selectedProviderList.length;
            };

            $scope.configureProvider = function(provider) {
                $location.path("/providers/" + provider.id);
            };

            // Select an provider on a page.
            $scope.selectProvider = function(providerInfo) {
                if (typeof providerInfo !== "undefined") {
                    if (providerInfo.rowSelected) {
                        selectedProviderList.push(providerInfo.id);

                        // Sync 'Select All' checkbox status when a new selction/unselection
                        // is made.
                        $scope.allRowsSelected = $scope.filteredList.every(function(item) {
                            return item.rowSelected;
                        });
                    } else {
                        selectedProviderList = selectedProviderList.filter(function(item) {
                            return item !== providerInfo.id;
                        });

                        // Unselect Select All checkbox.
                        $scope.allRowsSelected = false;
                    }
                }

                // Update the selected count tracker.
                $scope.totalSelectedProviders = selectedProviderList.length;
            };

            // Clear all selections by unchecking all checkboxes in all pages.
            $scope.clearAllSelections = function(event) {
                event.preventDefault();
                event.stopPropagation();

                selectedProviderList = [];
                $scope.filteredList.forEach(function(item) {
                    item.rowSelected = false;
                });

                $scope.checkdropdownOpen = false;
                $scope.allRowsSelected = false;
                $scope.totalSelectedProviders = 0;
            };

            // update table on search
            $scope.searchList = function() {
                $scope.fetch();
            };

            // have your filters all in one place - easy to use
            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy"),
                startFrom: $filter("startFrom"),
                limitTo: $filter("limitTo")
            };

            // update table
            $scope.fetch = function() {
                var filteredList = [];

                // filter list based on search text
                if ($scope.meta.filterValue !== "") {
                    filteredList = filters.filter($scope.providers, $scope.meta.filterValue, false);
                } else {
                    filteredList = $scope.providers;
                }

                // sort the filtered list
                if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                    filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                }

                // update the total items after search
                $scope.meta.totalItems = filteredList.length;

                // filter list based on page size and pagination
                if ($scope.meta.totalItems > _.min($scope.meta.pageSizes)) {
                    var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;
                    var limit = $scope.meta.pageSize;

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

                var countNonSelected = 0;

                // Add rowSelected attribute to each item in the list to track selections.
                filteredList.forEach(function(item) {

                    // Select the rows if they were previously selected on this page.
                    if (selectedProviderList.indexOf(item.id) !== -1) {
                        item.rowSelected = true;
                    } else {
                        item.rowSelected = false;
                        countNonSelected++;
                    }
                });

                $scope.filteredList = filteredList;

                // Clear the 'Select All' checkbox if at least one row is not selected.
                $scope.allRowsSelected = (filteredList.length > 0) && (countNonSelected === 0);

                return filteredList;
            };

            $scope.init = function() {
                $scope.providers = ProvidersService.get_providers();
                $scope.fetch();
            };

            // first page load
            $scope.init();
        }
        ProviderController.$inject = ["$scope", "$filter", "$location", "ProvidersService", "PAGE"];
        app.controller("ProvidersController", ProviderController);


    });
