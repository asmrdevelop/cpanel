/*
# cjt/directives/quickFilterItemDirective.js                                     Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.directives.quickFilterItem", [
            "cjt2.templates"
        ]);

        /**
         * Directive that renders a quick filter item
         * these are then used within the quickFiltersDirective
         * @attribute {String}  value - qa referencable id (transcluded)
         *
         * @example
         *  <quick-filter-item value="">[% locale.maketext('All') %]</quick-filter-item>
         */

        var RELATIVE_PATH = "libraries/cjt2/directives/";
        var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

        module.directive("quickFilterItem", function() {

            var TEMPLATE = TEMPLATES_PATH + "quickFilterItem.phtml";

            return {
                restrict: "E",
                scope: {
                    value: "@",
                    parentID: "@id",
                    linkTitle: "@title"
                },
                require: "^quickFilters",
                replace: true,
                transclude: true,
                templateUrl: TEMPLATE,
                link: function($scope, $element, $attrs, $ctrl) {
                    $scope.quickFilter = {
                        value: $attrs.value,
                        active: false
                    };
                    $scope.selectFilter = $ctrl.selectFilter.bind($ctrl);
                    $scope.isActive = function isActive() {
                        return $scope.quickFilter.value === $ctrl.getSelected();
                    };
                    $ctrl.addFilter($scope.quickFilter);
                }
            };

        });
    }
);
