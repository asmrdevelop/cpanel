/*
# cjt/directives/toggleSortDirective.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// http://nadeemkhedr.wordpress.com/2013/09/01/build-angularjs-grid-with-server-side-paging-sorting-filtering/
// Use with permission.
// ------------------------------------------------------------

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE) {

        // Constants
        var ASCENDING = "asc";
        var DESCENDING = "desc";
        var DEFAULT_ASCENDING_TITLE = LOCALE.maketext("Ascending");
        var DEFAULT_DESCENDING_TITLE = LOCALE.maketext("Descending");

        var module = angular.module("cjt2.directives.toggleSort", [
            "cjt2.templates"
        ]);

        /**
         * Directive that helps with column sorting for tabular datasets.
         *
         * @name toggleSort
         * @attribute {Binding}  sortMeta      Meta-Data Model where the current sort information is stored.
         *                                     This object includes the following fields:
         *                                        {String} sortBy        - current field.
         *                                        {String} sortDirection - current sort direction for that field.
         *                                        {String} sortType      - type of sort for that field.
         * @attribute {Value}    sortField     The name of the field in the model to sort when this is active.
         * @attribute {Value}    [sortType]    Optional, the type of sort to perform for this field. e.g. lexical, numeric, defaults to "" which lets the server decide the sort algorithm.
         * @attribute {Value}    [sortReverse] Optional, if true, inverts the display logic for ascending and descending for the arrow.
         * @attribyte {Boolean}  [sortReverseDefault] Optional. If given, the default sort for this column will be descending rather than ascending.
         * @attribute {Function} [onsort]      Optional function triggered when a sort operation happens. Has the following callback signature:
         *
         *                                         function sort(sortMeta) {
         *                                             // your code
         *                                         }
         *
         *                                        where sortMeta has the same fields as the sortMeta attribute above.
         * @example
         *
         * In your markup:
         *
         * <div toggle-sort
         *      onsort="sortList"
         *      sort-meta="meta"
         *      sort-field="db">
         *     Database
         * </div>
         *
         * <div toggle-sort
         *      onsort="sortList"
         *      sort-meta="meta"
         *      sort-type="numeric"
         *      sort-field="id">
         *     ID
         * </div>
         *
         * In your JavaScript initially set
         *
         * $scope.meta = {
         *     sortBy: "id",
         *     sortDirection: "asc",
         *     sortType: ""
         * };
         *
         * $scope.sortList = function(meta) {
         *     // update html history
         *     // trigger backend call
         *     // apply a filter or some other
         *     // operation based on the sort properties.
         * };
         *
         */
        module.directive("toggleSort", function() {
            var RELATIVE_PATH = "libraries/cjt2/directives/toggleSortDirective.phtml";
            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                restrict: "EA",
                transclude: true,
                replace: true,
                scope: {
                    sortMeta: "=",
                    sortType: "@",
                    sortField: "@",
                    sortReverse: "@",
                    sortAscendingTitle: "@",
                    sortDescendingTitle: "@",
                    sortReverseDefault: "@",
                    onsort: "&"
                },

                compile: function(element, attributes) {

                    if (!attributes["sortAscendingTitle"]) {
                        attributes["sortAscendingTitle"] = DEFAULT_ASCENDING_TITLE;
                    }

                    if (!attributes["sortDescendingTitle"]) {
                        attributes["sortDescendingTitle"] = DEFAULT_DESCENDING_TITLE;
                    }

                    return function(scope, element, attributes) {

                        /**
                         * Get the title text for the sort direction control.
                         *
                         * @method getTitle
                         */
                        scope.getTitle = function() {
                            return _getDir() === ASCENDING ? attributes["sortAscendingTitle"] : attributes["sortDescendingTitle"];
                        };

                        /**
                         * Gets the sort direction, as seen by the end user
                         *
                         * @method _getDir
                         * @private
                         * @return {String}   A string corresponding to the sort direction.
                         */
                        function _getDir() {
                            return !angular.isDefined(scope.sortReverse) ?
                                scope.sortMeta.sortDirection : scope.sortMeta.sortDirection === ASCENDING ?
                                    DESCENDING : ASCENDING;
                        }
                        scope.getDir = _getDir;

                        /**
                         * Sets the sort direction
                         *
                         * @method _setDir
                         * @private
                         * @param {String} newdir   The new direction for the sorting.
                         */
                        function _setDir(newdir) {
                            scope.sortMeta.sortDirection = !angular.isDefined(scope.sortReverse) ?
                                newdir : newdir === ASCENDING ?
                                    DESCENDING : ASCENDING;
                            return _getDir();
                        }

                        /**
                         * Toggle the sort direction on the selected column
                         */
                        scope.sort = function() {
                            var meta = scope.sortMeta;

                            if (meta.sortBy === scope.sortField) {
                                meta.sortDirection = meta.sortDirection === ASCENDING ? DESCENDING : ASCENDING; // Just flipping this around, so no need to use the setter/getter
                            } else {
                                meta.sortBy = scope.sortField;
                                _setDir( angular.isUndefined(scope.sortReverseDefault) ? ASCENDING : DESCENDING );
                                meta.sortType = scope.sortType;
                            }

                            // Make sure onsort exists on the parent scope before executing it
                            var onsort = scope.onsort();
                            if (angular.isFunction(onsort)) {
                                onsort(meta);
                            }
                        };
                    };
                }
            };
        });
    }
);
