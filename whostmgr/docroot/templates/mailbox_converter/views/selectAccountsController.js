/*
# templates/mailbox_converter/views/selectAccountsController.js
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
        "cjt/directives/triStateCheckbox",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "selectAccountsController", [
                "$scope",
                "$filter",
                "indexService",
                "$route",
                function($scope, $filter, indexService) {
                    $scope.$parent.ready = false;

                    var selected_mailbox_format = indexService.get_format();

                    // Get the stored accounts in case we've come back to this step after selecting
                    var _accounts = indexService.get_accounts();
                    var accounts = [];
                    angular.forEach(_accounts, function(value) {
                        value.selected = value.selected || 0;
                        accounts.push( value );
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
                        limitTo: $filter("limitTo")
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

                    $scope.toggleCheckAll = function(arr, attr, val) {
                        arr.forEach(function(item, index) {
                            arr[index][attr] = val;
                        });
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

                        filteredList = filters.filter(filteredList, { "mailbox_format": "!" + selected_mailbox_format });

                        // sort the filtered list
                        if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                            filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? true : false);
                        }

                        // update the total items after search
                        $scope.meta.totalItems = filteredList.length;

                        // filter list based on page size and pagination
                        if ($scope.meta.totalItems > min_value_in_array($scope.meta.pageSizes)) {
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

                        $scope.filteredAccounts = filteredList;

                        return filteredList;
                    };

                    // first page load
                    $scope.fetch();

                    $scope.$watch("accounts", function( newValue ) {
                        indexService.set_accounts(newValue);
                        var selected_accounts = filters.filter(newValue, { "selected": 1 });
                        if (selected_accounts.length) {
                            $scope.$parent.ready = true;
                        } else {
                            $scope.$parent.ready = false;
                        }
                    }, true
                    );

                    $scope.pagination_msg = function() {
                        return LOCALE.maketext("Showing [numf,_1] - [numf,_2] of [quant,_3,item,items]", $scope.meta.start, $scope.meta.limit, $scope.meta.totalItems);
                    };
                }
            ]
        );

        return controller;
    }
);
