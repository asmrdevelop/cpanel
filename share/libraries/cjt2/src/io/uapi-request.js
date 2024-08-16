/*
# cjt/io/uapi-request.js                             Copyright 2022 cPanel, L.L.C.
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
 * Helper module to build requests for UAPI.
 *
 * @module cjt/io/uapi-request
 * @example
 *
 *  require(["cjt/io/uapi-request"], function(REQUEST) {
 *      var request = new REQUEST.Class();
 *      request.initialize("module-name", "function-name");
 *      request.addArgument("arg1", "value1");
 *      request.addArgument("arg2", "value2");
 *      request.addPaging(1, 10);
 *      request.addFilter("column1", "contains", "a");
 *      request.addSorting("columnt1", REQUEST.sort.ASCENDING);
 *
 *      var callObject = requets.getRunArguments();
 *  });
 */
define([
    "lodash",
    "cjt/io/request",
], function(_, generateRequestClass) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/uapi-request";
    var MODULE_DESC = "Contains a helper object used to build UAPI call parameters.";
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
     * @private
     * @return {Object} Initialized abstract request metadata object
     */
    var _getEmptyRequestMeta = function() {
        return {
            paginate: {
                start: 0,
                start_record: 0,
                size: DEFAULT_PAGE_SIZE
            },
            filter: [],
            sort: []
        };
    };

    var Base = generateRequestClass(3, _getEmptyRequestMeta);

    /**
     * Helper class for generating UAPI requests.
     * @class
     * @augments module:cjt/io/request:Request
     * @exports  module:cjt/io/uapi-request:UapiRequest
     */
    var UapiRequest = function() {
        Base.call(this);
    };

    /**
     * @static
     * @property {enum} [sort] Contains sorting constants
     */
    UapiRequest.sort  = {
        ASCENDING: ASCENDING,
        DESCENDING: DESCENDING
    };

    UapiRequest.prototype = Object.create(Base.prototype, {

        /**
         * Adds the paging meta data to the run parameters in UAPI format
         *
         * @method  addPaging
         * @instance
         * @param {Number} startPage Start page
         * @param {Number} page_size  Optional page size, inherits from previous initialization.
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addPaging: {
            value: function(startPage, pageSize) {
                this.validateMeta("addPaging");
                this.meta.paginate = this.meta.paginate || {};

                // if the size is equal to the "All" page size sentinel value,
                // abort pagination
                if (pageSize === -1 || this.meta.paginate.size === -1) {
                    return;
                }

                pageSize = pageSize || this.meta.paginate.size || DEFAULT_PAGE_SIZE;

                this.meta.paginate.start = ((startPage - 1) * pageSize) + 1;
                this.meta.paginate.size = pageSize;

                return this;
            }
        },

        /**
         * Clears the paging rules from the meta data.
         *
         * @method  clearPaging
         * @instance
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        clearPaging: {
            value: function() {
                this.validateMeta("clearPaging");
                delete this.meta.paginate;
                return this;
            }
        },

        /**
         * Add sorting rules meta data to the run parameters in API2 format.
         *
         * @method  addSorting
         * @instance
         * @param {String} field     Name of the field to sort on.
         * @param {String} direction asc or dsc. Defaults to asc.
         * @param {String} type      Sort types supported by the API. Defaults to
         * equality
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addSorting: {
            value: function(field, direction, type) {
                this.validateMeta("addSorting");

                var sortField = field;
                var sortDir = direction || "asc";
                var sortType = type || "";

                if (sortField) {
                    var uapiSortRule = (sortDir === "asc" ? "" : "!") + sortField;

                    // If we have a type, the we need the complex array format
                    if (sortType !== "") {
                        uapiSortRule = [uapiSortRule, sortType];
                    }

                    // Store the rule.
                    if (this.meta.sort) {
                        this.meta.sort.push(uapiSortRule);
                    } else {
                        this.meta.sort = [uapiSortRule];
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
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
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
         * Add filter rules meta data to the run parameters in UAPI format.
         *
         * @method  addFilter
         * @instance
         * @param {String|Array} key  Field name or array of three elements [key, operator, value].
         * @param {String} [operator] Comparison operator to use.  Optional if the first parameter is an array.
         * @param {String} [value]    Value to compare the field with. Optional if the first parameter is an array.
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
         * @throws When this.meta is not an object.
         */
        addFilter: {
            value: function(key, operator, value) {
                this.validateMeta("addFilter");
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
                return this;
            }
        },

        /**
         * Clear the meta data for the filter.
         *
         * @method  clearFilter
         * @instance
         * @returns {UapiRequest} The current instance of the request so calls can be chained.
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

    UapiRequest.prototype.constructor = UapiRequest; // Repair the constructor.

    // Publish the component
    return {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,
        Class: UapiRequest
    };
});
