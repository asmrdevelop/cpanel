/*
# cjt/io/api2-request.js                          Copyright(c) 2020 cPanel, L.L.C.
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
// 1) Unlike UAPI, the API2 does not conform to a strict results layout.
// As development continues we will likely have to add various exceptions
// to the getData() and getError() methods...
// -----------------------------------------------------------------------

// TODO: Add tests for these

/**
 *
 * @module cjt/io/api2-request
 * @example

    require(["lodash","cjt/io/api2-request"], function(_, REQUEST) {
        // TODO:
    });
 */
define(["lodash", "cjt/util/test"], function(_, TEST) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/api2-request"; // requirejs(["cjt/io/api2-request"], function(REQUEST) {}); -> cjt/io/api2-request.js || cjt/io/api2-request.min.js
    var MODULE_DESC = "Contains a helper object used to build API2 call parameters.";
    var MODULE_VERSION = 2.0;

    // ------------------------------
    // Constants
    // ------------------------------
    var DEFAULT_PAGE_SIZE = 10;
    var ASCENDING = 0;
    var DESCENDING = 1;

    /**
     * Creates an empty metadata object
     * @method  _getEmptyRequestMeta
     * @return {Object} Initialized abstract request metadata object
     */
    var _getEmptyRequestMeta = function() {
        return {
            paginate: {
                start_page: 0,
                start_record: 0,
                page_size: DEFAULT_PAGE_SIZE
            },
            filter: [],
            sort: []
        };
    };


    // -----------------------------------------------------------------------------------
    // Api request Api2 calls.
    //
    // @class Api2Request
    //
    // -----------------------------------------------------------------------------------
    var Api2Request = function() {

        /**
         * API version number to use for UAPI.
         *
         * @class  Api2Request
         * @property {Number} version
         */
        this.version = 2;

        /**
         * API module name for UAPI call.  Represents the module in <Module>::<Call>().
         *
         * @class  Api2Request
         * @property {String} module
         */
        this.module = "";

        /**
         * API function name for UAPI call.  Represents the call in <Module>::<Call>().
         *
         * @class  Api2Request
         * @property {String} func
         */
        this.func = "";

        /**
         * Collection of arguments for the API call.
         *
         * @class  WhmV1Request
         * @property {Object} args
         */
        this.args = {};

        /**
         * API call meta data for the UAPI call.  Should be a hash with names for
         * each meta data parameter passed to the UAPI call. This data is used to
         * control properties such as sorting, filters and paging.
         *
         * @class  Api2Request
         * @property {Object} meta
         */
        this.meta = _getEmptyRequestMeta();

        /**
         * Number to add to an auto argument.
         *
         * @class  WhmV1Request
         * @property {Number} auto
         */
        this.auto = 1;
    };

    /**
     *
     * @static
     * @class Api2Request
     * @property {enum} [sort] Contains sorting constants
     */
    Api2Request.sort  = {
        ASCENDING: ASCENDING,
        DESCENDING: DESCENDING
    };

    Api2Request.prototype = {

        /**
         * Initialize the sync data
         *
         * @class  Api2Request
         * @method  initialize
         * @param  {String} module Name of the module where the API function exists.
         * @param  {String} func   Name of the function to call.
         * @param  {Object} data   Data for the function call.
         * @param  {Object} meta   Meta-data such as sorting, filtering, paging and similar data for the api call.
         */
        initialize: function(module, func, data, meta) {
            this.module = module;
            this.func = func;
            this.data = data || {};
            this.meta = meta || {};
            this.auto = 1;

            return this;    // for chaining
        },

        /**
         * Adds an argument
         *
         * @class  WhmV1Request
         * @method  addArgument
         * @param {String} name   Name of the argument
         * @param {Object} value  Value of the argument
         * @param {Boolean} [isAuto] Optional, will add an auto counter to this argument
         */
        addArgument: function(name, value, isAuto) {
            if (!isAuto) {
                this.args[name] = value;
            } else {
                this.args[name + this.auto] = value;
            }
        },

        /**
         * Removes an argument
         *
         * @class  WhmV1Request
         * @method removeArgument
         * @param  {[type]}  name   [description]
         * @param  {Boolean} isAuto [description]
         * @return {[type]}         [description]
         */
        removeArgument: function(name, isAuto) {
            if (!isAuto) {
                this.args[name] = null;
                delete this.args[name];
            } else {
                this.args[name + this.auto] = null;
                delete this.args[name + this.auto];
            }
        },

        /**
         * Make the argument counter increment.
         * @class  WhmV1Request
         * @method  incrementAuto
         * @return {Number} Current value of the increment.
         */
        incrementAuto: function() {
            this.auto++;
            return this.auto;
        },

        /**
         * Clears the arguments
         *
         * @class  WhmV1Request
         * @method  clearArguments
         * @param {String} name   Name of the argument
         * @param {Object} value  Value of the argument
         */
        clearArguments: function() {
            this.args = {};
        },

        /**
         * Adds the paging meta data to the run parameters in UAPI format
         *
         * @class  Api2Request
         * @method  addPaging
         * @param {Number} start   Start page
         * ATTR apiIndex.
         * @param {Number} size    Optional page size, inherits from previous initialization.
         */
        addPaging: function(start, size) {

            // if the size is equal to the "All" page size sentinel value,
            // abort pagination
            if (size === -1 || this.meta.size === -1) {
                return;
            }

            size = size || this.meta.size || 10;

            this.meta.paginate = this.meta.paginate || {};
            this.meta.paginate.start = ((start - 1) * size) + 1;
            this.meta.paginate.size = size;
        },

        /**
         * Clears the paging rules from the meta data.
         *
         * @class  Api2Request
         * @method  clearPaging
         */
        clearPaging: function() {
            delete this.meta.paginate;
        },

        /**
         * Add sorting rules meta data to the run parameters in API2 format.
         *
         * @class  Api2Request
         * @method  addSorting
         * @param {Hash} [options] Optional options passed in from the outside
         * @param {String} field     Name of the field to sort on.
         * @param {String} direction asc or dsc. Defaults to asc.
         * @param {String} type      Sort types supported by the API. Defaults to
         * equality
         */
        addSorting: function(field, direction, type) {
            var sortField = field;
            var sortDir = direction || "asc";
            var sortType = type || "";

            if (sortField) {
                var api2SortRule = (sortDir === "asc" ? "" : "!") + sortField;

                // If we have a type, the we need the complex array format
                if (sortType !== "") {
                    api2SortRule = [api2SortRule, sortType];
                }

                // Store the rule.
                if (this.meta.sort) {
                    this.meta.sort.push(api2SortRule);
                } else {
                    this.meta.sort = [api2SortRule];
                }
            }
        },

        /**
         * Clear the sorting rules meta data.
         *
         * @class Api2Request
         * @method  clearSorting
         */
        clearSorting: function() {
            delete this.meta.sort;
        },


        /**
         * Add filter rules meta data to the run parameters in UAPI format.
         *
         * @class  Api2Request
         * @method  addFilter
         * @param {String|Array} key  Field name or array of three elements [key, operator, value].
         * @param {String} [operator] Comparison operator to use.  Optional if the first parameter is an array.
         * @param {String} [value]    Value to compare the field with. Optional if the first parameter is an array.
         */
        addFilter: function(key, operator, value) {
            var filter;
            if (_.isArray(key)) {
                filter = key;
            } else {
                filter = [key, operator, value];
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
        },

        /**
         * Clear the meta data for the filter.
         *
         * @class Api2Request
         * @method  clearFilter
         */
        clearFilter: function() {
            delete this.meta.filter;
        },

        /**
         * Build the API2 call data structure.
         *
         * @class  Api2Request
         * @method getRunArguments
         * @param  {String Array} [fields]  List of fields to extract.
         * @param  {Object }      [context] Context to call callbacks with.
         * @return {Object}       Packages up an api call base on collected information.
         */
        getRunArguments: function(fields, context) {
            return {
                version: this.version,
                module: this.module,
                func: this.func,
                meta: this.meta,
                args: this.args
            };
        }
    };

    // Publish the component
    return {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,
        Class: Api2Request
    };
});
