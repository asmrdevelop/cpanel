/*
# cjt/directives/selectSortDirective.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE) {

        var ASCENDING  = "asc";
        var DESCENDING = "desc";
        var DEFAULT_ASCENDING_TITLE = LOCALE.maketext("Ascending");
        var DEFAULT_DESCENDING_TITLE = LOCALE.maketext("Descending");

        var module = angular.module("cjt2.directives.selectSort", [
            "cjt2.templates"
        ]);

        /**
         * Directive that provides a select box to sort a tabular dataset by a single column in ascending or descending order.
         *
         * @name cpSelectSort
         * @attribute {Binding}   sortMeta      Meta-Data Model where the sort properties are stored.
         *                                      Sort properties required are sortDirection, sortBy, and sortType.
         * @attribute {Binding}   sortFields    An array of sortField objects following the pattern:
         *                                      The field corresponds to the api.sort.a.field
         *                                      The sortType corresponds to api.sort.a.method, e.g. lexical, numeric, ipv4
         *                                      The sortReverse boolean will reverse the direction of the sortDirection
         *                                          property on the metadata object.
         *                                      The label is the text that will be shown on the select option.
         * @attribute {Attribute} defaultField  The default sort field.
         * @attribute {Attribute} defaultDir    The default sort direction.
         * @attribute {Attribute} idSuffix      The suffix for the IDs on the select and direction arrow.
         * @attribute {Attribute} label         The text for the label that precedes the select box.
         * @attribute {Function}  onsort        Function triggered when a sort operation happens.
         *                                      Can handle initiating the backend request or just be used as a callback.
         * @callback onsort
         * @param {Reference} sortMeta      Meta-Data Model where the sort properties are stored.
         *                                  Sort properties required are sortDirection, sortBy, and sortType.
         * @param {Boolean}   defaultSort   If true, this sort is being executed because the default sort attributes
         *                                  were set and not due to user action.
         *
         * @example
         *
         * <cp-select-sort sort-meta="meta"
         *                 onsort="sortList"
         *                 sort-fields="sortFields"
         *                 default-field="id"
         *                 default-dir="desc">
         * </cp-select-sort>
         *
         * Where:
         *
         * $scope.sortFields = [
         *     {
         *         field: "staged",
         *         label: LOCALE.maketext("Unpublished"),
         *         sortReverse: true
         *     },
         *     {
         *         field: "vendor_id",
         *         label: LOCALE.maketext("Vendor")
         *     },
         *     {
         *         field: "id",
         *         label: LOCALE.maketext("ID"),
         *         sortType: "numeric"
         *     }
         * ];
         */
        module.directive("cpSelectSort", function() {
            var suffixCount = 0;
            var RELATIVE_PATH = "libraries/cjt2/directives/selectSortDirective.phtml";

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                restrict: "E",
                scope: {
                    sortFields: "=",
                    sortMeta: "=",
                    sortAscendingTitle: "@",
                    sortDescendingTitle: "@",
                    onsort: "&",
                    label: "@"
                },

                controller: ["$scope", "$attrs", function($scope, $attrs) {

                    /**
                     * Gets the sort direction, as seen by the end user.
                     *
                     * @method _getDir
                     * @private
                     * @return {String}   A string corresponding to the sort direction.
                     */
                    function _getDir() {

                        // If we're not reversing, just provide the direction as-is. Otherwise, provide the opposite.
                        return !$scope.fieldMap[$scope.sortMeta.sortBy].sortReverse ?
                            $scope.sortMeta.sortDirection : $scope.sortMeta.sortDirection === ASCENDING ?
                                DESCENDING : ASCENDING;
                    }
                    $scope.getDir = _getDir;

                    /**
                     * Sets the sort direction.
                     *
                     * @method _setDir
                     * @private
                     * @param {String} newdir   The new direction for the sorting.
                     */
                    function _setDir(newdir) {

                        // If we're not reversing, just set with the new direction. Otherwise, set with the opposite.
                        $scope.sortMeta.sortDirection = !$scope.fieldMap[$scope.sortMeta.sortBy].sortReverse ?
                            newdir : newdir === ASCENDING ?
                                DESCENDING : ASCENDING;

                        return _getDir();
                    }

                    /**
                     * Get the title text for the sort direction control.
                     *
                     * @method getTitle
                     */
                    $scope.getTitle = function() {
                        return _getDir() === ASCENDING ? $attrs["sortAscendingTitle"] : $attrs["sortDescendingTitle"];
                    };

                    /**
                     * Changes the sort direction and executes the onsort callback if defined.
                     *
                     * @method sort
                     * @param  {Boolean} changeDir      If true, the sort direction will flip.
                     * @param  {Boolean} defaultSort    If true, this is an initial sort triggered because of default
                     *                                  values passed in as attributes.
                     */
                    $scope.sort = function(changeDir, defaultSort) {
                        var meta = $scope.sortMeta;

                        // Update the sort direction
                        if (changeDir) {
                            meta.sortDirection = meta.sortDirection === ASCENDING ? DESCENDING : ASCENDING; // Just flipping this around, so no need to use the setter/getter
                        } else if (!defaultSort) {
                            _setDir(ASCENDING); // Changing sort fields, so go back to ascending
                        }

                        // Update the sortType
                        meta.sortType = $scope.fieldMap[meta.sortBy].sortType;

                        // Make sure onsort exists on the parent scope before executing it
                        var onsort = $scope.onsort();
                        if (angular.isFunction(onsort)) {
                            onsort(meta, defaultSort);
                        }
                    };

                    // Set up a map to easily access the sortField objects.
                    // The array of sortFields is necessary so that the order can be preserved in the select.
                    $scope.fieldMap = {};
                    $scope.sortFields.forEach(function(obj) {
                        $scope.fieldMap[obj.field] = obj;
                    });

                    // Set the suffix from the attribute or generic counter
                    $scope.idSuffix = $attrs.idSuffix || suffixCount++;

                    // Set the metadata object properties if defaults have been provided.
                    // Process the defaultField if it exists
                    if ($attrs.defaultField) {

                        // Check if the default sort field is valid
                        $scope.validDefaultProvided = $scope.sortFields.some(function(sortField) {
                            return sortField.field === $attrs.defaultField;
                        });

                        // If valid, set the default sort field
                        if ($scope.validDefaultProvided) {
                            $scope.sortMeta.sortBy = $attrs.defaultField;
                        }
                    }

                    // Set the sortBy to the first item in the sortFields array if it's not
                    // set in the metadata object and a default field wasn't provided.
                    if (!$scope.sortMeta.sortBy) {
                        $scope.sortMeta.sortBy = $scope.sortFields[0].field;
                    }

                    // Process the default sort direction if it exists
                    if ($attrs.defaultDir === DESCENDING || $attrs.defaultDir === ASCENDING) {
                        _setDir($attrs.defaultDir);
                        $scope.validDefaultProvided = true;
                    }

                    // If there's no defaultDir and the direction isn't set in the metadata, let's default to asc
                    else if ($scope.sortMeta.sortDirection !== DESCENDING && $scope.sortMeta.sortDirection !== ASCENDING) {
                        _setDir(ASCENDING);
                    }

                }],

                compile: function(element, attributes) {

                    // Set the asc/desc title attributes if they aren't set
                    if (!attributes["sortAscendingTitle"]) {
                        attributes["sortAscendingTitle"] = DEFAULT_ASCENDING_TITLE;
                    }

                    if (!attributes["sortDescendingTitle"]) {
                        attributes["sortDescendingTitle"] = DEFAULT_DESCENDING_TITLE;
                    }

                    // Set the label attribute if it isn't set
                    if (!attributes["label"]) {
                        attributes["label"] = LOCALE.maketext("Sort by");
                    }

                    return function(scope, element, attrs) {

                        // Once everything is set up, go ahead and fire the callback if
                        // valid defaults were provided.
                        if (scope.validDefaultProvided) {
                            scope.sort(false, true);
                        }
                    };
                },
            };
        });
    }
);
