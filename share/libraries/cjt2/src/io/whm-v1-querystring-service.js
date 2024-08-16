/*
# cjt/io/whm-v1-querystring-service.js            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [

        // Libraries
        "angular",
        "ngRoute"
    ],
    function(angular) {

        // CONSTANTS
        var LETTERS = "abcdefghijklmnopqrstuvwxyz";
        var DEFAULT_PAGE_SIZE = 10;
        var DEFAULT_PAGE_SIZES = [10, 20, 50, 100];
        var SORT_ASCENDING = "asc";
        var SORT_DESCENDING = "desc";
        var FILTER_PROPERTY_PATTERN = new RegExp("^api\\.filter\\.[" + LETTERS + "]*\\..*");
        var SORT_PROPERTY_PATTERN = new RegExp("^api\\.sort\\.[" + LETTERS + "]*\\..*");

        var module = angular.module("cjt2.services.whm.query", [
            "ngRoute"
        ]);

        /**
         * Setup the rule models API service
         */
        module.factory("queryService", ["$location", "$routeParams", function($location, $routeParams) {

            // State
            var lastFilter = 0;
            var lastSort = 0;

            /*
             * Make a filter field prefix string
             *
             * @private
             * @method _makeFilterFieldPrefix
             * @param [name] Optional name, if not provided, it will use one of the auto-generated one.
             * @return {String}
             */
            var _makeFilterFieldPrefix = function(name) {
                if (!name) {
                    name = LETTERS[lastFilter];
                    lastFilter++;
                }
                return "api.filter." + name + ".";
            };

            /**
             * Make a sort field prefix string
             *
             * @private
             * @method _makeSortFieldPrefix
             * @param [name] Optional name, if not provided, it will use one of the auto-generated one.
             * @return {String}
             */
            var _makeSortFieldPrefix = function(name) {
                if (!name) {
                    name = LETTERS[lastSort];
                    lastSort++;
                }
                return "api.sort." + name + ".";
            };

            /**
             * Test if paging is enabled.
             *
             * @private
             * @return {Boolean}
             */
            var _routeHasPaging = function() {
                return $routeParams["api.chunk.enable"] === "1";
            };

            /**
             * Test if sorting is enabled.
             *
             * @private
             * @return {Boolean}
             */
            var _routeHasSorting = function() {
                return $routeParams["api.sort.enable"] === "1";
            };

            /**
             * Test if search filtering is enabled
             * @type {Boolean}
             */
            var _routeHasSearch = function() {
                return $routeParams["api.filter.enable"] === "1";
            };


            /**
             * Convert the whm filter property into the generic version.
             *
             * @private
             * @method _normalizeFilterFieldName
             * @param  {String} name
             * @return {String}      Normalized name for the field
             */
            var _normalizeFilterFieldName = function(name) {
                switch (name) {
                    case "field":
                        return "field";
                    case "type":
                        return "type";
                    case "arg0":
                        return "value";
                }
                return name;
            };

            /**
             * Convert the whm sort property into the generic version.
             *
             * @private
             * @method _normalizeSortFieldName
             * @param  {String} name
             * @return {String}      Normalized name for the field
             */
            var _normalizeSortFieldName = function(name) {
                switch (name) {
                    case "field":
                        return "field";
                    case "method":
                        return "method";
                    case "reverse":
                        return "direction";
                }
                return name;
            };

            /**
             * Clear the search flags
             *
             * @method _clearSearchFlags
             * @private
             */
            var _clearSearchFlags = function() {
                $location.search("api.filter.enable", null);
                $location.search("api.filter.verbose", null);
            };


            // return the factory interface
            return {

                query: {

                    /**
                     * Add a query-string parameter
                     *
                     * @method addParameter
                     * @param {String} name
                     * @param {String} value
                     */
                    addParameter: function(name, value) {
                        $location.search(name, value);
                    },

                    /**
                     * Remove a query-string parameter by name
                     *
                     * @method removeParameter
                     * @param  {String} name
                     */
                    removeParameter: function(name) {
                        var search = $location.search();
                        for (var item in search) {
                            if (search.hasOwnProperty(item) &&
                                item === name) {
                                delete search[item];
                            }
                        }
                        $location.search(search);
                    },

                    /**
                     * Clear the filter querystring parameters.
                     * @method clearFilter
                     */
                    clearSearch: function() {
                        var search = $location.search();
                        for (var item in search) {
                            if (search.hasOwnProperty(item) &&
                                /^api\.filter/.test(item)) {
                                delete search[item];
                            }
                        }
                        $location.search(search);
                        lastFilter = 0;
                    },


                    /**
                     * Add a search query to the url
                     *
                     * @method  addSearchField
                     * @param {String} field Name of the field to filter on.
                     * @param {String} type  A valid search type
                     * @param {String} value Value to compare against
                     * @param {String} [name] Optional name for the property used in constructing the url parameter name. If left off, its auto generated.
                     */
                    addSearchField: function(field, type, value, name) {
                        if (!name) {
                            name = _makeFilterFieldPrefix();
                        }
                        var search = $location.search();
                        if (!search["api.filter.enable"]) {
                            $location.search("api.filter.enable", 1);
                        }
                        if (!search["api.filter.verbose"]) {
                            $location.search("api.filter.verbose", 1);
                        }
                        $location.search(name + "field", field);
                        $location.search(name + "type", type);
                        $location.search(name + "arg0", value);
                    },

                    /**
                     * Clear the search flags
                     *
                     * @method clearSearchFlags
                     */
                    clearSearchFlags: _clearSearchFlags,

                    /**
                     * Clear the specific search query from the url
                     *
                     * @method  clearSearchField
                     * @param {String} field Name of the field to filter on.
                     * @param {String} type  A valid search type
                     * @param {String} value Value to compare against
                     * @param {Boolean} clearFlags if true will clear the filter flags, otherwise it will leave them alone.
                     * @return {}            [description]
                     */
                    clearSearchField: function(field, type, value, clearFlags) {
                        if (typeof (clearFlags) === "undefined" && clearFlags === true ) {
                            _clearSearchFlags();
                        }

                        var search = $location.search();
                        var name = "";
                        for (var key in search) {
                            if (search.hasOwnProperty(key)) {
                                var matches =  key.match(/api\.filter\.(.)\.field/);
                                var typeDefined = typeof (type) !== "undefined";
                                var valueDefined = typeof (value) !== "undefined";
                                if (matches &&
                                    search[key] === field &&
                                    (!typeDefined || search["api.filter." + matches[1] + ".type"] === type) &&
                                    (!valueDefined || search["api.filter." + matches[1] + ".arg0"] === value)) {
                                    name =  matches[1];
                                    break;
                                }
                            }
                        }

                        if (name) {

                            // Found it so remove it
                            $location.search("api.filter." + name + ".field", null);
                            $location.search("api.filter." + name + ".type", null);
                            $location.search("api.filter." + name + ".arg0", null);
                        }
                    },

                    /**
                     * Update the pagination query string parameters
                     *
                     * @method updatePagination
                     * @param  {Number} page       Page to select. 1 is the first page.
                     * @param  {Number} [pageSize] Optional page size, defaults to 10
                     */
                    updatePagination: function(page, pageSize) {
                        if (typeof (pageSize) === "undefined") {
                            pageSize = DEFAULT_PAGE_SIZE;
                        }

                        $location.search("api.chunk.enable", 1);
                        $location.search("api.chunk.verbose", 1);
                        $location.search("api.chunk.size", pageSize);
                        $location.search("api.chunk.start", ( (page - 1) * pageSize) + 1);
                    },

                    /**
                     * Clear the pagination query string properties.
                     *
                     * @method clearPagination
                     */
                    clearPagination: function() {
                        $location.search("api.chunk.enable", null);
                        $location.search("api.chunk.verbose", null);
                        $location.search("api.chunk.size", null);
                        $location.search("api.chunk.start", null);
                    },

                    /**
                     * Add the sort query string parameters
                     *
                     * @method addSortField
                     * @param  {String} field       Field to sort by.
                     * @param  {String} [type]      Optional type of sort to apply. Defaults to lexical.
                     * @param  {String} [direction] Optional sort direction: asc or desc, defaults to ascending
                     * @param  {String} [name]        optional name, if not provided, it will auto-generate a name
                     */
                    addSortField: function(field, type, direction, name) {
                        direction = direction || SORT_ASCENDING;
                        type      = type || ""; // Apply the server default of lexical.

                        $location.search("api.sort.enable", 1);

                        var prefix = _makeSortFieldPrefix(name);

                        $location.search(prefix + "field", field);
                        $location.search(prefix + "method", type || "");
                        $location.search(prefix + "reverse", direction === SORT_ASCENDING ? 0 : 1);
                    },

                    /**
                     * Clear the sort query string parameters.
                     * @method clearSort
                     */
                    clearSort: function() {
                        var search = $location.search();
                        for (var item in search) {
                            if (search.hasOwnProperty(item) &&
                                /^api\.sort/.test(item)) {
                                delete search[item];
                            }
                        }
                        $location.search(search);
                        lastSort = 0;
                    },

                },

                route: {

                    /**
                     * Add a query-string parameter
                     *
                     * @method addParameter
                     * @param {String} name
                     * @param {String} value
                     */
                    getParameter: function(name) {
                        return $routeParams[name];
                    },

                    /**
                     * Test if paging is enabled.
                     * @return {Boolean}
                     */
                    hasPaging: _routeHasPaging,


                    /**
                     * Test if sorting is enabled
                     * @type {[type]}
                     */
                    hasSorting: _routeHasSorting,

                    /**
                     * Test if search filtering is enabled
                     * @type {Boolean}
                     */
                    hasSearch: _routeHasSearch,

                    /**
                     * Get the collection of sort rule on the route
                     *
                     * @method route.getSorting
                     * @return {Array} Array of sorts where each element is:
                     *       {Object}
                     *           {String} field Field filtered.
                     *           {String} method Comparison type used.
                     *           {String} direction  SORT_ASCENDING or  SORT_DESCENDING
                     */
                    getSorting: function() {
                        var key;
                        var sorts = [];
                        var tmp = {};
                        for (key in $routeParams) {
                            if ($routeParams.hasOwnProperty(key) &&
                                SORT_PROPERTY_PATTERN.test(key)) {
                                var parts = key.split(".");
                                var name = parts[2];
                                var fieldName = _normalizeSortFieldName(parts[3]);

                                if (!tmp[name]) {
                                    tmp[name] = {};
                                }

                                if (fieldName === "direction") {
                                    tmp[name][fieldName] = $routeParams[key] === "1" ? SORT_DESCENDING : SORT_ASCENDING;
                                } else {
                                    tmp[name][fieldName] = $routeParams[key];
                                }
                            }
                        }

                        for (key in tmp) {
                            if (tmp.hasOwnProperty(key)) {
                                sorts.push(tmp[key]);
                            }
                        }

                        return sorts;
                    },

                    /**
                     * Get the collection of filters on the route.
                     *
                     * @method route.getSearch
                     * @return {Array} Array of filters where each element is:
                     *       {Object}
                     *           {String} field Field filtered.
                     *           {String} type  Comparison type used.
                     *           {String} value Value passed to the comparison.
                     */
                    getSearch: function() {
                        var key;
                        var filters = [];
                        var tmp = {};
                        for (key in $routeParams) {
                            if ($routeParams.hasOwnProperty(key) &&
                                FILTER_PROPERTY_PATTERN.test(key)) {
                                var parts = key.split(".");
                                var name = parts[2];
                                var fieldName = _normalizeFilterFieldName(parts[3]);
                                if (!tmp[name]) {
                                    tmp[name] = {};
                                }
                                tmp[name][fieldName] = $routeParams[key];
                            }
                        }

                        for (key in tmp) {
                            if (tmp.hasOwnProperty(key)) {
                                filters.push(tmp[key]);
                            }
                        }

                        return filters;
                    },


                    /**
                     * Gets the search value for a specific field.
                     *
                     * @method getSearchFieldValue
                     * @param {String} field Name of the field to filter on.
                     * @return {String}      Value of the field.arg0 property or nothing
                     */
                    getSearchFieldValue: function(field) {
                        var result;
                        for (var key in $routeParams) {
                            if ($routeParams.hasOwnProperty(key)) {
                                var matches =  key.match(/api\.filter\.(.)\.field/);
                                if (matches &&  $routeParams[key] === field) {
                                    result = $routeParams["api.filter." + matches[1] + ".arg0"];
                                    break;
                                }
                            }
                        }
                        return result;
                    },

                    /**
                     * Gets the page size in the route
                     *
                     * @method getPageSize
                     * @param  {Number} [defPageSize] Optional default page size if not in the route.
                     * @return {Number}
                     */
                    getPageSize: function(defPageSize) {
                        if (_routeHasPaging()) {
                            return parseInt($routeParams["api.chunk.size"], 10);
                        } else {
                            return defPageSize || DEFAULT_PAGE_SIZE;
                        }
                    },

                    /**
                     * Gets the page in the route.
                     *
                     * @method getPage
                     * @param  {Number} pageSize Page size for the request.
                     * @param  {Number} [defPage]  Optional default page if not in the route, defaults to 1
                     * @return {Number}
                     */
                    getPage: function(pageSize, defPage) {
                        if (typeof ($routeParams["api.chunk.start"]) !== "undefined")  {
                            return Math.floor(parseInt($routeParams["api.chunk.start"], 10) / pageSize) + 1;
                        } else {
                            return defPage || 1;
                        }
                    },

                    /**
                     * Gets the sort properties in the route
                     *
                     * @note Assumes only one sort in the request.
                     * @method getSortProperties
                     * @param  {String} defField   Default field to sort.
                     * @param  {String} defType    Default type of sort to use.
                     * @param  {String} defDirection Default direction, either asc or desc.
                     * @return {Object}
                     *            {String} field     Field sorted by.
                     *            {String} type      Type of sort used.
                     *            {String} direction asc or desc
                     */
                    getSortProperties: function(defField, defType, defDirection) {
                        var result;

                        if (_routeHasSorting()) {
                            var search = $routeParams;
                            var name = "";
                            for (var key in search) {
                                if (search.hasOwnProperty(key)) {
                                    var matches =  key.match(/api\.sort\.(.)\.field/);
                                    if (matches) {
                                        name =  matches[1];
                                        break;
                                    }
                                }
                            }

                            if (name) {

                                // Found it so remove it
                                result = {
                                    field: search["api.sort." + name + ".field"],
                                    type: search["api.sort." + name + ".type"],
                                    direction: (search["api.sort." + name + ".reverse"] === "1" ? SORT_DESCENDING : SORT_ASCENDING ),
                                };
                            }
                        } else {
                            result = {
                                field: defField,
                                type: defType,
                                direction: defDirection,
                            };
                        }

                        return result;
                    }
                },

                prefetch: {
                    succeeded: function(prefetch) {
                        return prefetch.metadata.result !== 0;
                    },

                    failed: function(prefetch) {
                        return prefetch.metadata.result === 0;
                    },

                    getMetaMessage: function(prefetch) {
                        return prefetch.metadata.reason || "";
                    }
                },

                /**
                 * Default page size.
                 * @type {Number}
                 */
                DEFAULT_PAGE_SIZE: DEFAULT_PAGE_SIZE,

                /**
                 * List of default page sizes
                 * @type {Array} Array of numbers.
                 */
                DEFAULT_PAGE_SIZES: DEFAULT_PAGE_SIZES,

                /**
                 * Constant Sort Ascending Rule
                 * @type {String}
                 */
                SORT_ASCENDING: SORT_ASCENDING,

                /**
                 * Constant Sort Descending Rule
                 * @type {String}
                 */
                SORT_DESCENDING: SORT_DESCENDING
            };
        }]);
    }
);
