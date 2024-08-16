/*
# whostmgr/docroot/templates/index.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

// Then load the application dependencies
// Reference libraries for POTENTIAL loading.
define('app/index',[
    "angular",
    "lodash",
    "cjt/core",
    "cjt/modules",
    "cjt/directives/toggleSortDirective",
    "cjt/directives/searchDirective",
    "cjt/directives/pageSizeDirective",
    "cjt/filters/startFromFilter",
    "cjt/decorators/paginationDecorator"
], function(angular, _) {

    "use strict";

    var appName = "whm.listSubdomains";

    return function() {

        angular.module(appName, ["cjt2.config.whm.configProvider", "cjt2.whm"]);

        require(["cjt/bootstrap"], function(BOOTSTRAP) {

            // Creates an new angular module instance for your application.
            var app = angular.module(appName);
            app.value("PAGE", PAGE);

            app.controller("tableCtrl", ["$scope", "$filter", function($scope, $filter) {

                $scope.subdomains = [];

                PAGE.domains.forEach(function(domaindata) {
                    domaindata.subdomains.forEach(function(subdomain) {
                        subdomain.user = domaindata.user;
                        subdomain.domain = domaindata.domain;
                        subdomain.parked = domaindata.parked;
                        subdomain.user = domaindata.user;
                        $scope.subdomains.push(subdomain);
                    });
                });

                var filters = {
                    filter: $filter("filter"),
                    orderBy: $filter("orderBy"),
                    startFrom: $filter("startFrom"),
                    limitTo: $filter("limitTo")
                };

                $scope.meta = {

                    // sort settings
                    sortReverse: false,
                    sortBy: "domain",
                    sortDirection: "asc",

                    // search settings
                    filterValue: PAGE.searchDomain ? PAGE.searchDomain : "",

                    // pager settings
                    maxPages: 5,
                    totalItems: $scope.subdomains.length,
                    currentPage: 1,
                    pageSize: 10,
                    pageSizes: [10, 20, 50, 100],
                    start: 0,
                    limit: 10
                };

                $scope.sortList = function(meta) {
                    $scope.fetch();
                };

                $scope.selectPage = function(currentPage) {
                    $scope.fetch();
                };

                $scope.selectPageSize = function(pageSize) {
                    $scope.fetch();
                };

                $scope.searchList = function(searchString) {
                    $scope.fetch();
                };

                $scope.fetch = function() {

                    var filteredList = $scope.subdomains;

                    if ($scope.meta.filterValue !== "") {
                        filteredList = filters.filter($scope.subdomains, $scope.meta.filterValue, false);
                    } else {
                        filteredList = $scope.subdomains;
                    }

                    if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                        filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection !== "asc");
                    }

                    $scope.meta.totalItems = filteredList.length;

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

                    $scope.filteredList = filteredList;
                };

                $scope.fetch();
            }]);

            // Attach the angular app to the DOM.
            BOOTSTRAP(document, appName);
        });

    };

});

