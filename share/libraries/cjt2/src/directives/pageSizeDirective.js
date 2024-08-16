/*
# cjt/directives/pageSizeDirective.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/util/locale",
        "cjt/filters/qaSafeIDFilter",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, _, CJT, parse, LOCALE) {

        var module = angular.module("cjt2.directives.pageSize", [
            "cjt2.templates"
        ]);

        module.directive("pageSize", ["$parse", "pageSizeConfig",
            function($parse, pageSizeConfig) {
                var RELATIVE_PATH = "libraries/cjt2/directives/pageSizeDirective.phtml";

                // A value to assign to the page size entry - 'All'
                var PAGE_SIZE_ALL_VALUE = -1;

                return {
                    restrict: "EA",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    require: "ngModel",
                    replace: true,
                    scope: {
                        "parentID": "@id",
                        "totalItems": "=",
                        "allowedSizes": "=",
                        "showAll": "=",
                        "autoHide": "="
                    },

                    link: function(scope, element, attrs, ngModel) {

                        if (!ngModel) {
                            return; // do nothing if no ng-model on the directive
                        }

                        function getAllowedPageSizes() {
                            var meta = {};
                            meta.allowedSizes = scope.allowedSizes || pageSizeConfig.allowedSizes;
                            meta.totalItems = scope.totalItems || pageSizeConfig.totalItems;
                            meta.showAllItems = scope.showAll;

                            if (scope.showAll) {
                                PAGE_SIZE_ALL_VALUE = scope.totalItems || -1;
                            }

                            var sizes = meta.allowedSizes.slice(0);

                            sizes.sort(function(a, b) {
                                return a - b;
                            });

                            sizes = sizes.map(function(size) {
                                return {
                                    label: size,
                                    value: size
                                };
                            });

                            if (meta.showAllItems) {

                                // Set to 'All' if no other values exist
                                sizes.push({
                                    label: LOCALE.maketext("All"),
                                    value: PAGE_SIZE_ALL_VALUE
                                });
                            }

                            // Removing filtering because it's breaking some interfaces
                            // When a page doens't have an "All" and has a totalitems
                            // less than the smallest size (10) it breaks.

                            if (sizes.length === 1 && sizes[0].value === meta.totalItems) {
                                scope.pageSize = sizes[0].value;
                            } else if (sizes.filter(function(size) {
                                return size.value === scope.pageSize;
                            }).length === 0) {

                                // ensure pageSize is an option, otherwise set to lowest option
                                scope.pageSize = sizes[0].value;
                            }


                            return sizes;

                        }

                        if (attrs.allowedSizes) {
                            scope.$parent.$watch($parse(attrs.allowedSizes), function() {
                                scope.options = getAllowedPageSizes();
                            });
                        }

                        if (attrs.totalItems) {
                            scope.$parent.$watch($parse(attrs.totalItems), function() {
                                scope.options = getAllowedPageSizes();
                            });
                        }

                        if (attrs.showAll) {
                            scope.$parent.$watch($parse(attrs.showAll), function() {
                                scope.options = getAllowedPageSizes();
                            });
                        }

                        ngModel.$render = function() {
                            scope.pageSizeTitle = LOCALE.maketext("Page Size");
                            scope.pageSize = ngModel.$viewValue;
                        };

                        scope.$watch("pageSize", function(newValue, oldValue) {
                            if (newValue === oldValue) {
                                return; // No update on same value;
                            }
                            if (!newValue) {
                                return; // New value is null or invalid
                            }
                            ngModel.$setViewValue(scope.pageSize);
                        });

                        scope.$watch("totalItems", function() {
                            scope.options = getAllowedPageSizes();
                        });

                        scope.options = getAllowedPageSizes();

                    }
                };
            }
        ]);

        module.constant("pageSizeConfig", {
            allowedSizes: [10, 20, 50, 100],
            totalItems: 0,
            showAllItems: false
        });

    }
);
