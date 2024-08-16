/*
# cjt/directives/quickFiltersDirective.js                                        Copyright(c) 2020 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, _, CJT) {

        var module = angular.module("cjt2.directives.quickFilters", [
            "cjt2.templates"
        ]);

        /**
         * Directive that renders a quick filters wrapper
         * @attribute {String}  id - qa referencable id (transcluded)
         * @attribute {String}  title - if exists, the title pill for the filters
         * @attribute {String}  active - default active filter key
         * @attribute {String}  onFilterChange - function called on filter change
         *
         * @example
         * <quick-filters title="[% locale.maketext('Filter:') %]" active="meta.quickFilterValue" on-filter-change="fetch()">
         *   <quick-filter-item value="">[% locale.maketext('All') %]</quick-filter-item>
         *   <quick-filter-item value="wildcards">[% locale.maketext('Wildcard Domains') %]</quick-filter-item>
         *   <quick-filter-item value="nonwildcards">[% locale.maketext('Non Wildcard Domains') %]</quick-filter-item>
         * </quick-filters>
         */

        var RELATIVE_PATH = "libraries/cjt2/directives/";
        var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

        module.directive("quickFilters", ["$timeout", function($timeout) {

            var TEMPLATE = TEMPLATES_PATH + "quickFilters.phtml";

            return {
                restrict: "E",
                scope: {
                    id: "@?id",
                    title: "@?title",
                    active: "=active",
                    onFilterChange: "&"
                },
                transclude: true,
                controller: ["$scope", function($scope) {

                    $scope.active = $scope.active || "";

                    var filters = [];

                    this.addFilter = function addFilter(filter) {
                        filters.push(filter);
                        if (filter.value === $scope.active) {
                            filter.active = true;
                        }
                    };

                    $scope.$watch("active", function(newvalue, oldvalue) {

                        if (newvalue === oldvalue) {
                            return;
                        }

                        $scope.active = newvalue;

                        filters.forEach(function(filter) {
                            if (filter.value === newvalue) {
                                filter.active = true;
                            } else {
                                filter.active = false;
                            }
                        });
                    });


                    function selectFilter(selection) {
                        $scope.active = selection;

                        filters.forEach(function(filter) {
                            if (filter.value === selection) {
                                filter.active = true;
                            } else {
                                filter.active = false;
                            }
                        });

                        // timeout was necessary to ensure no race condition
                        $timeout($scope.onFilterChange.bind($scope), 10);
                    }

                    this.selectFilter = selectFilter;

                }],
                templateUrl: TEMPLATE
            };

        }]);
    }
);
