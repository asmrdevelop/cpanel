/*
# cjt/directives/responsiveSortDirective.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/directives/responsiveSortInsertDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT) {

        var module = angular.module("cjt2.directives.responsiveSort", [
            "cjt2.templates"
        ]);

        /**
         * This directive wraps a set of toggleSort directives and generates/inserts a cp-select-sort
         * directive into the wrapping element. See the documentation for the cp-responsive-sort-insert,
         * cp-select-sort, and toggleSort directives for more information. Note that the toggleSort
         *
         * @name cp-responsive-sort
         * @attribute {Attribute} defaultField  The default sort field for the selectSort.
         * @attribute {Attribute} defaultDir    The default sort direction for the selectSort.
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
         *      <span class="hidden-xs col-sm-2">
         *          <toggle-sort id="sortID"
         *                       class="nowrap"
         *                       onsort="sortList"
         *                       sort-meta="meta"
         *                       sort-type="numeric"
         *                       sort-field="id">
         *              [% locale.maketext('ID') %]
         *          </toggle-sort>
         *      </span>
         *      <span class="hidden-xs col-sm-2">
         *          <toggle-sort id="sortMessage"
         *                       class="nowrap"
         *                       onsort="sortList"
         *                       sort-dir="meta"
         *                       sort-field="meta_msg">
         *              [% locale.maketext('Message') %]
         *          </toggle-sort>
         *      </span>
         * </li>
         *
         * In this example the cp-responsive-sort directive is wrapping 3 toggle-sort directives.
         * The generated selectSort directive will be inserted where the cp-responsive-sort-insert
         * element is placed.
         */
        module.directive("cpResponsiveSort", function() {
            return {
                restrict: "A",
                scope: true,

                // This controller is basically just here to enforce the parent-child relationship.
                controller: function() {},

                // The compile function is used because we need to access the DOM before the
                // toggleSort directives are processed. Otherwise, the transcluded text will
                // be missing and we cannot derive our option labels.
                compile: function(element, attrs) {

                    // This obj will eventually have consolidated sortBy, sortDir, and onsort keys
                    // for the selectSort directive. The sortFields key is an array of sortField
                    // objects which are consumed by the selectSort directive.
                    var parsed = {
                        sortFields: []
                    };

                    // Generate an array of objects from the toggleSort directives that are
                    // found within the element. These objects contain key/val pairs of the
                    // associated attributes.
                    var toggleSorts = Array.prototype.map.call(element.find("toggle-sort"), function(elem) {
                        elem = angular.element(elem);
                        return {
                            onsort: elem.attr("onsort"),
                            sortType: elem.attr("sort-type"),
                            sortReverse: angular.isDefined(elem.attr("sort-reverse")),
                            sortMeta: elem.attr("sort-meta"),
                            sortField: elem.attr("sort-field"),
                            sortLabel: elem.text().trim()
                        };
                    });

                    // Go through the list of bound attributes for each toggleSort found and
                    // ensure that they are uniform. Put all of the validated data into the
                    // "parsed" var.
                    toggleSorts.forEach(function(toggleSort) {
                        ["sortMeta", "onsort"].forEach(function(property) {

                            // Ignore omitted onsort attributes
                            if (!toggleSort.onsort) {
                                return;
                            }

                            if (!parsed[property]) { // For the first run-through
                                if (toggleSort[property]) {
                                    parsed[property] = toggleSort[property];
                                } else {
                                    throw new ReferenceError("Malformed/incomplete toggle-sort directive found in descendant tree. Responsive sort directive cannot proceed.");
                                }
                            } else if (toggleSort[property] !== parsed[property]) {
                                throw new Error("The responsive sort directive cannot handle more than one " + property + " property at a time.");
                            }
                        });

                        // Create the actual sortField object to be inserted into the array
                        if (toggleSort.sortField && toggleSort.sortLabel) {
                            parsed.sortFields.push({
                                label: toggleSort.sortLabel,
                                field: toggleSort.sortField,
                                sortType: toggleSort.sortType,
                                sortReverse: toggleSort.sortReverse
                            });
                        } else {
                            throw new ReferenceError("Malformed/incomplete toggle-sort directive found in descendant tree. Responsive sort directive cannot proceed.");
                        }
                    });

                    return {

                        // The scope needs to be set up in the pre-linking function because the
                        // post-linking order will start with the child directive and thus the
                        // scope wouldn't be ready.
                        pre: function link(scope, element, attrs) {

                            // Set up the view model for the selectSort
                            scope.selectSort = {
                                parsed: parsed,
                                attrs: {
                                    defaultField: attrs.defaultField,
                                    defaultDir: attrs.defaultDir
                                }
                            };
                        }
                    };
                }
            };
        });
    }
);
