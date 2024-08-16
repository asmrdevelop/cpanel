/*
# cjt/directives/responsiveSortInsertDirective.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/directives/selectSortDirective",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        var module = angular.module("cjt2.directives.responsiveSortInsert", [
            "cjt2.directives.responsiveSort",
            "cjt2.templates"
        ]);

        /**
         * This directive is meant to only be used as a child of the responsiveSortDirective.
         * The directive element will be replaced by a generated cp-select-sort directive.
         * See the documentation for the cp-responsive-sort directive for more information on
         * its available attributes and options.
         *
         * @name cp-responsive-sort-insert
         * @attribute {Attribute} idSuffix   The suffix use for the IDs on the select element and direction arrow.
         * @attribute {Attribute} label      The text for the label that precedes the select box.
         *
         * @example
         *
         * <li class="list-table-header row" cp-responsive-sort>
         *     <span class="visible-xs col-xs-8">
         *         <cp-responsive-sort-insert default-field="id" default-dir="desc"></cp-responsive-sort-insert>
         *     </span>
         *     <span class="hidden-xs col-sm-2">
         *          <toggle-sort id="sortVendor"
         *                       class="nowrap"
         *                       onsort="sortList"
         *                       sort-meta="meta"
         *                       sort-field="vendor_id">
         *          [% locale.maketext('Vendor') %]
         *          </toggle-sort>
         *      </span>
         */
        module.directive("cpResponsiveSortInsert", ["$http", "$compile", "$interpolate", "$templateCache", function($http, $compile, $interpolate, $templateCache) {
            var RELATIVE_PATH = "libraries/cjt2/directives/responsiveSortInsertDirective.phtml";
            return {
                restrict: "E",
                scope: true,
                require: "^^cpResponsiveSort",

                compile: function() {
                    return function(scope, element, attrs, parentController) {
                        scope.selectSort.attrs.idSuffix  = attrs.idSuffix;
                        scope.selectSort.attrs.label     = attrs.label;

                        /**
                         * Interpolates values from scope.selectSort into the directive template,
                         * compiles the interpolated template, and inserts it into the DOM.
                         *
                         * @method _interpolateAndInsert
                         * @param  {Object}  scope      The directive scope.
                         * @param  {String}  template   The directive template.
                         */
                        function _interpolateAndInsert(scope, template) {

                            // Interpolation needs to be explicitly executed before the compile step
                            // because the selectSortDirective is not set up to $observe its attributes
                            // and will error out if it sees eval expressions on scope-bound attributes.
                            template = $interpolate(template)(scope.selectSort);
                            template = $compile(template)(scope);
                            element.replaceWith(template);
                        }

                        var templateURL = RELATIVE_PATH;

                        // Check the templateCache to see if we already have the template. If not,
                        // go grab it. We can't use the regular template/templateURL directive
                        // definition properties because we need to interpolate manually.
                        var template = $templateCache.get(templateURL);
                        if (template) {
                            _interpolateAndInsert(scope, template);
                        } else {
                            $http.get(CJT.buildFullPath(templateURL))
                                .success(function(template) {
                                    _interpolateAndInsert(scope, template);
                                    $templateCache.put(templateURL, template);
                                });
                        }
                    };
                }
            };
        }]);
    }
);
