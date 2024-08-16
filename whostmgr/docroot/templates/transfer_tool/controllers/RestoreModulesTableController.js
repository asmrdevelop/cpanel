/*
# templates/transfer_tool/controllers/RestoreModulesTableController.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                                         All rights reserved.
# copyright@cpanel.net                                                    http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* jshint -W003 */
/* jshint -W098*/

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("Modules", PAGE.modules);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        function RestoreModulesTableController($scope, $filter, modules) {
            $scope.modules = modules;

            angular.forEach($scope.modules, function(value, key) {
                value.summary = value.summary.join(" ");
                if (value.restricted_summary) {
                    value.restricted_summary = value.restricted_summary.join(" ");
                }
            }, $scope.modules);

            // meta information
            $scope.meta = {

                // sort settings
                sortReverse: false,
                sortBy: "module",
                sortDirection: "asc",

                // pager settings
                maxPages: 5,
                totalItems: $scope.modules.length,

                filterValue: "",
            };

            // initialize filter list
            $scope.filteredList = $scope.modules;
            $scope.showPager = true;

            // have your filters all in one place - easy to use
            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy")
            };

            // update table
            $scope.fetch = function() {
                var filteredList = [];

                // filter list based on search text
                if ($scope.meta.filterValue !== "") {
                    filteredList = filters.filter($scope.modules, $scope.meta.filterValue, false);
                } else {
                    filteredList = $scope.modules;
                }

                // sort the filtered list
                if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                    filteredList = filters.orderBy(filteredList, $scope.meta.sortBy,
                        $scope.meta.sortDirection === "asc" ? false : true);
                }

                // update the total items after search
                $scope.meta.totalItems = filteredList.length;

                $scope.filteredList = filteredList;

                return filteredList;
            };

            // update the table on sort
            $scope.sortList = $scope.fetch;

            // update table on search
            $scope.searchList = $scope.fetch;

            // first page load
            $scope.fetch();
        }


        RestoreModulesTableController.$inject = ["$scope", "$filter", "Modules"];
        var controller = app.controller("RestoreModulesTableController", RestoreModulesTableController);

        return controller;

    }
);
