/*
# templates/external_auth/views/UsersController.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W003 */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/decorators/paginationDecorator",
    ],
    function(angular, _) {

        var UsersController = function($scope, $filter, $location, UsersService, ProvidersService) {
            var _this = this;

            $scope.users = [];
            $scope.providers = [];

            // meta information
            $scope.meta = {

                // sort settings
                sortReverse: false,
                sortBy: "label",
                sortDirection: "asc",

                // pager settings
                maxPages: 5,
                totalItems: $scope.users.length,
                currentPage: 1,
                pageSize: 20,
                pageSizes: [20, 50, 100, 500],
                start: 0,
                limit: 10,

                filterValue: "",
            };

            // initialize filter list
            $scope.filteredList = $scope.users;
            $scope.showPager = true;

            /**
             * Initialize the variables required for
             * row selections in the table.
             */
            $scope.checkdropdownOpen = false;

            // This updates the selected tracker in the 'Selected' Badge.
            $scope.totalSelectedUsers = 0;
            var selectedUserList = [];

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

            $scope.configureUser = function(provider) {
                $location.path("/providers/" + provider.id);
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

            $scope.manage_user = function(username) {
                $location.path("/users/" + username);
            };

            $scope.get_providers_for = function(user) {
                var providers = [];
                angular.forEach(user.links, function(provider_type) {
                    angular.forEach(provider_type, function(value, key) {
                        var provider = ProvidersService.get_provider_by_id(key);
                        if (provider) {
                            providers.push(provider);
                        }
                    });
                });
                return providers;
            };

            // update table
            $scope.fetch = function() {
                var filteredList = [];

                // filter list based on search text
                if ($scope.meta.filterValue !== "") {
                    filteredList = filters.filter($scope.users, $scope.meta.filterValue, false);
                } else {
                    filteredList = $scope.users;
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
                    if (selectedUserList.indexOf(item.id) !== -1) {
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
                $scope.users = UsersService.get_users();
                $scope.providers = ProvidersService.get_enabled_providers();
                $scope.fetch();
            };

            // first page load
            $scope.init();

            return _this;
        };

        var app = angular.module("App");

        UsersController.$inject = ["$scope", "$filter", "$location", "UsersService", "ProvidersService"];
        var controller = app.controller("UsersController", UsersController);

        return controller;
    }
);
