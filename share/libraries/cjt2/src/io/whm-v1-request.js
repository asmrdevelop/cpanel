/*
# cjt/io/whm-v1-request.js                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* eslint-env amd */
/* --------------------------*/

// -----------------------------------------------------------------------
// DEVELOPER NOTES:
// -----------------------------------------------------------------------
// TODO: Add better argument checking:
//  * no negative pages
//  * no sort field provided
//
// See the xit() tests...
// -----------------------------------------------------------------------

/**
 * Helper module to build requests for WHM API v1.
 *
 * @module cjt/io/whm-v1-request
 * @example
 *
 *  require([cjt/io/whm-v1-request"], function(REQUEST) {
 *      var request = new REQUEST.Class();
 *      request.initialize("module-name", "function-name");
 *      request.addArgument("arg1", "value1");
 *      request.addArgument("arg2", "value2");
 *      request.addPaging(1, 10);
 *      request.addFilter("column1", "contains", "a");
 *      request.addSorting("column1", REQUEST.sort.ASCENDING);
 *
 *      var callObject = request.getRunArguments();
 *  });
 */
define([
    "lodash",
    "cjt/io/request"
], function(
        _,
        generateRequestClass
    ) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/whm-v1-request";
    var MODULE_DESC = "Contains a helper object used to build WHM v1 API call parameters.";
    var MODULE_VERSION = 2.0;

    // ------------------------------
    // Constants
    // ------------------------------
    var DEFAULT_PAGE_SIZE = 10;
    var ASCENDING = 0;
    var DESCENDING = 1;
    var DEFAULT_FILTER_OPERATOR = ""; // AS OF 11.46 this will default to "compare" when empty string is passed.

    /**
     * Creates an empty metadata object
     *
     * @method  _getEmptyRequestMeta
     * @private
     * @return {Object} Initialized abstract request metadata object
     */
    var _getEmptyRequestMeta = function() {
        return {
            paginate: _getEmptyPaginate(),
            filter: [],
            sort: []
        };
    };

    /**
     * Creates an empty paginate object
     *
     * @method  _getEmptyRequestMeta
     * @private
     * @return {Object} Initialized abstract request metadata object
     */
    var _getEmptyPaginate = function() {
        return {
            enabled: false,
            start_page: 0,
            start_record: 0,
            page_size: DEFAULT_PAGE_SIZE
        };
    };

    var Base = generateRequestClass(1, _getEmptyRequestMeta);

    /**
     * Helper class for generating WHM API1 requests.
     *
     * @class
     * @augments module:cjt/io/request:Request
     * @exports  module:cjt/io/whm-v1-request:WhmV1Request
     */
    var WhmV1Request = function() {
        Base.call(this);
    };

    /**
     * @static
     * @property {enum} [sort] Contains sorting constants
     */
    WhmV1Request.sort  = {
        ASCENDING: ASCENDING,
        DESCENDING: DESCENDING
    };

    WhmV1Request.prototype = Object.create(Base.prototype, {

        /**
         * Initialize the request
         *
         * @method  initialize
         * @instance
         * @param  {String} module Name of the module where the API function exists.
         * @param  {String} func   Name of the function to call.
         * @param  {Object} args   Arguments for the function call.
         * @param  {Object} meta   Meta-data such as sorting, filtering, paging and similar data for the api call.
         * @param  {RequestOptions} opts   Use to set additional options for the request.
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         */
        initialize: {
            value: function(module, func, args, meta, opts) {
                if (opts && opts.realNamespaces && module) {
                    func = module + "/" + func;
                    module = null;
                }

                Base.prototype.initialize.call(this, module, func, args, meta, opts);
                this.meta = meta ||
                    this.meta && Object.keys(this.meta).length > 0 ?
                    this.meta :
                    _getEmptyRequestMeta();
                return this;    // for chaining
            }
        },

        /**
         * Adds the paging meta data to the run parameters in WHM API1 format
         *
         * @method  addPaging
         * @instance
         * @param {Number} startPage Start page
         * @param {Number} pageSize  Optional page size, inherits from previous initialization.
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addPaging: {
            value: function(startPage, pageSize) {
                this.validateMeta("addPaging");

                // if the size is equal to the "All" page size sentinel value,
                // abort pagination
                if (pageSize === -1 || this.meta.paginate.page_size === -1) {
                    return;
                }

                pageSize = pageSize || this.meta.paginate.page_size || DEFAULT_PAGE_SIZE;

                this.meta.paginate = this.meta.paginate || {};
                this.meta.paginate.enabled = true;
                this.meta.paginate.start_page = startPage;
                this.meta.paginate.start_record = ((startPage - 1) * pageSize) + 1;
                this.meta.paginate.page_size = pageSize;

                return this;
            }
        },

        /**
         * Clears the paging rules from the meta data.
         *
         * @method  clearPaging
         * @instance
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        clearPaging: {
            value: function() {
                this.validateMeta("clearPaging");
                this.meta.paginate = _getEmptyPaginate();
                return this;
            }
        },

        /**
         * Add sorting rules meta data to the run parameters in API2 format.
         *
         * @method  addSorting
         * @instance
         * @param {Hash} [options] Optional options passed in from the outside
         * @param {String} field     Name of the field to sort on.
         * @param {String} direction asc or dsc. Defaults to asc.
         * @param {String} type      Sort types supported by the API. Defaults to
         * equality
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addSorting: {
            value: function(field, direction, type) {
                this.validateMeta("addSorting");

                var sortField = field;
                var sortDir = direction || "asc";
                var sortType = type || "";

                if (sortField || sortField === "") {
                    var sortRule = (sortDir === "asc" ? "" : "!") + sortField;

                    // If we have a type, the we need the complex array format
                    if (sortType !== "") {
                        sortRule = [sortRule, sortType];
                    }

                    // Store the rule.
                    if (this.meta.sort) {
                        this.meta.sort.push(sortRule);
                    } else {
                        this.meta.sort = [sortRule];
                    }
                }
                return this;
            }
        },

        /**
         * Clear the sorting rules meta data.
         *
         * @method  clearSorting
         * @instance
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        clearSorting: {
            value: function() {
                this.validateMeta("clearSorting");
                delete this.meta.sort;
                return this;
            }
        },


        /**
         * Add filter rules meta data to the run parameters in API format.
         *
         * @method  addFilter
         * @instance
         * @param {String|Array} key  Field name or array of three elements [key, operator, value].
         * @param {String} [operator] Comparison operator to use.  Optional if the first parameter is an array or you want the default sort. Can be undefined to get the default filter operator.
         * @param {String} [value]    Value to compare the field with. Optional if the first parameter is an array. Required if the first paramater is a string.
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addFilter: {
            value: function(key, operator, value) {
                this.validateMeta("addFilter");

                var filter;
                if (_.isArray(key)) {
                    filter = key;
                } else {
                    filter = [key, operator || DEFAULT_FILTER_OPERATOR, value];
                }

                // ---------------------------------------------
                // Building a structure that looks like this:
                //
                // [
                //      [ key1 , operator1, value1 ],
                //      [ key2 , operator2, value2 ],
                //      ...
                // ]
                // ---------------------------------------------
                if (filter) {
                    if (this.meta.filter) {
                        this.meta.filter.push(filter);
                    } else {
                        this.meta.filter = [filter];
                    }
                }
                return this;
            }
        },

        /**
         * Clear the meta data for the filter.
         *
         * @method  clearFilter
         * @instance
         * @returns {WhmV1Request} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        clearFilter: {
            value: function() {
                this.validateMeta("clearFilter");
                delete this.meta.filter;
                return this;
            }
        }
    });

    WhmV1Request.prototype.constructor = WhmV1Request; // Repair the constructor.


    // Publish the component
    return {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,
        Class: WhmV1Request
    };
});
