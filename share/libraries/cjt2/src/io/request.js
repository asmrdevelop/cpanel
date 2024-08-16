/*
# cjt/io/request.js                                  Copyright 2022 cPanel, L.L.C.
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
// TODO: Change api2 to use this base class.
// -----------------------------------------------------------------------

/**
 * This is a base class factory for request objects so that the common part of their implementation
 * can be shared between concrete classes.
 *
 * @module cjt/io/request
 * @see module:cjt/io/request:Request
 * @example
 *
 *   require(["cjt/io/request"], function(generateRequestClass) {
 *       var BaseClass = generateRequestClass(1, function { ... });
 *       var CustomRequest = function() {
 *           Base.call(this);
 *       };
 *       CustomRequest.prototype = Object.create(Base.prototype, {
 *           method: {
 *               value: function() {
 *                   ...
 *               }
 *           },
 *           booleanProperty: {
 *               value: false
 *           },
 *           stringProperty: {
 *               value: "custom"
 *           },
 *           ...
 *       });
 *       CustomRequest.prototype.constructor = CustomRequest;
 *
 *       var request = new CustomRequest();
 *       ...
 *   });
 */
define([
    "lodash",
    "cjt/util/analytics",
], function(_, ANALYTICS) {

    "use strict";

    /**
     * Factory method that generates a Request base class based on the parameters passed.
     *
     * @param  {Number} version
     * @param  {Function} getEmptyMeta Used to generate the meta data for a specific API version.
     * @return {Function} Constructor function for the specific Request class.
     */
    return function generateRequestClass(version, getEmptyMeta) {

        /**
         * Base class for all requests
         *
         * @class
         * @exports module:cjt/io/request:Request
         */
        var Request = function() {

            /**
             * API version number to use for UAPI.
             *
             * @property {Number} version
             * @instance
             */
            this.version = version;

            /**
             * API module name for UAPI call.  Represents the module in <Module>::<Func>() for
             * UAPI. Optional for WHM APIv1. If provided in WHM APIv1, it will append to the func
             * name as: <Module>_<Func>.
             *
             * @property {String} module
             * @instance
             */
            this.module = "";

            /**
             * API function name to call.  Represents the call in <Module>::<Func>() for
             * UAPI or the method to lookup in WHM API 1 from the dispatch tables.
             *
             * @property {String} func
             * @instance
             */
            this.func = "";

            /**
             * Collection of arguments for the API call.
             *
             * @property {Object} args
             * @instance
             */
            this.args = {};

            /**
             * Whether to send the request as JSON.
             *
             * For backward compatibility with code already using uapi-request or whm-v1-request, this
             * defaults to false. To enable JSON requests, set this to true or use the opts parameter
             * in the initialize() method to enable json.
             *
             * @property {Boolean} json
             * @instance
             */
            this.json = false;

            /**
             * API call meta data for the UAPI or WHM API v1 call.  Should be an object with names for
             * each meta data parameter passed to the UAPI call. This data is used to
             * control properties such as sorting, filters and paging.
             *
             * @property {Object} meta
             * @instance
             */
            this.meta = getEmptyMeta();

            /**
             * An object of auto-increment counters that will keep track of the numeric
             * suffixes appended to arguments when the 'auto' option is set to true.
             *
             * @property {Number} autoCounter
             * @instance
             */
            this.autoCounter = {
                __startVal: 1,
            };
        };

        Request.prototype = {

            /**
             * @global
             * @typedef RequestOptions
             * @type {Object}
             * @property {Boolean} [json] Use JSON request formatting. With this, the request arguments are sent to the
             * server as JSON in the body of the request and the Content-Type header is set to 'application/json'.
             * @property {Boolean} [realNamespaces] When true, treats the module as a real namespace, defaults to false. Only applicable to whm-v1.
             */

            /**
             * Initialize the request
             *
             * @method initialize
             * @instance
             * @param  {String}         module Name of the module where the API function exists.
             * @param  {String}         func   Name of the function to call.
             * @param  {Object}         data   Data for the function call.
             * @param  {Object}         meta   Meta-data such as sorting, filtering, paging and similar data for the API call.
             * @param  {RequestOptions} opts   Use to set additional options for the request.
             * @return {Request} The current instance of the request so calls can be chained.
             * @throws When data is not an object or undefined or null.
             */
            initialize: function(module, func, data, meta, opts) {
                this.module = module;
                this.func = func;
                this.setArguments(data || {});
                this.meta = meta || {};
                this.json = opts && opts.json ? true : false;

                return this;    // for chaining
            },

            /**
             * Sets the args property of the request. This can be used in lieu of addArgument when
             * using JSON API Requests so you can set the arguments to any arbitrary object.
             *
             * @method setArguments
             * @instance
             * @param {Object} args The data must be serializable as JSON
             * @throws When the args parameter is not an object.
             * @return {Request} The current instance of the request so calls can be chained.
             * @throws When args is not an object
             */
            setArguments: function(args) {
                if (typeof args !== "object") {
                    throw new TypeError("args parameter for 'setArgumetnObject' method must be an Object");
                }
                this.args = args;
                return this;
            },

            /**
             * Adds an argument
             *
             * @method addArgument
             * @instance
             * @param  {String}  name       Name of the argument to add.
             * @param  {Object}  value      Value of the argument.
             * @param  {Boolean} [isAuto]   Optional. If true, an automatic numeric suffix will be
             *                              appended to the argument name.
             * @return {Request} The current instance of the request so calls can be chained.
             * @throws When this.args is not an object.
             */
            addArgument: function(name, value, isAuto) {
                this.validateArgs("addArgument");
                if (!isAuto) {
                    this.args[name] = value;
                } else {
                    this.args[name + this.getAutoSuffix(name)] = value;
                    this.incrementAuto(name);
                }
                return this;
            },

            /**
             * Removes an argument
             *
             * @method removeArgument
             * @instance
             * @param  {String}  name       Name of the argument to remove.
             * @param  {Boolean} [isAuto]   Optional. If true, the last auto-incremented argument
             *                              with the same base name will be removed.
             * @return {Request} The current instance of the request so calls can be chained.
             * @throws When this.args is not an object.
             */
            removeArgument: function(name, isAuto) {
                this.validateArgs("removeArgument");
                name = isAuto ? (name + this.decrementAuto(name)) : name;
                this.args[name] = null;
                delete this.args[name];
                return this;
            },

            /**
             * Clears the arguments
             *
             * @method  clearArguments
             * @instance
             * @param {String} name   Name of the argument
             * @param {Object} value  Value of the argument
             * @return {Request} The current instance of the request so calls can be chained.
             */
            clearArguments: function() {
                this.args = {};
                this.autoCounter = {
                    __startVal: this.autoCounter.__startVal,
                };
                return this;
            },

            /**
             * Get the current auto increment value for the given property.
             *
             * @method getAutoSuffix
             * @instance
             * @param  {String} name The name of the property that will be incremented.
             * @return {Number} New value of the auto increment for the property.
             */
            getAutoSuffix: function(name) {
                if (_.isUndefined( this.autoCounter[name] ) ) {
                    this.autoCounter[name] = this.autoCounter.__startVal;
                }
                return this.autoCounter[name];
            },

            /**
             * Increment the suffix counter for a given argument name.
             *
             * @method incrementAuto
             * @instance
             * @param  {String} name The name of the property that will be incremented.
             * @return {Number} New value of the auto increment for the property.
             */
            incrementAuto: function(name) {
                return (this.autoCounter[name] = this.getAutoSuffix(name) + 1);
            },

            /**
             * Decrement the argument suffix counter for a given argument name. The
             * counter will never go below the __startVal.
             *
             * @method decrementAuto
             * @instance
             * @param  {String} name The name of the property that will be decremented.
             * @return {Number} New value of the auto increment for the property.
             */
            decrementAuto: function(name) {
                var currVal = this.getAutoSuffix(name);
                if (currVal > this.autoCounter.__startVal) {
                    this.autoCounter[name] = currVal - 1;
                }

                return this.autoCounter[name];
            },

            /**
             * Add analytics metadata to the API request. If the AnalyticsState object has already
             * been instantiated, any options passed will update the instance with those key/value
             * pairs while leaving omitted properties intact. If you wish to remove properties you
             * must reset the analytics metadata using clearAnaltyics() first.
             *
             * @method addAnalytics
             * @instance
             * @param  {Object} [options]   Optional hash of options to pass to the AnalyticsState
             *                              constructor. See cjt/util/analytics for details.
             * @return {Request} The current instance of the request so calls can be chained.
             */
            addAnalytics: function(options) {
                if (!this.analytics) {
                    this.analytics = ANALYTICS.create(options);
                } else {
                    this.analytics.update(options);
                }
                return this;
            },

            /**
             * Clears the analytics metadata from this API request.
             *
             * @method clearAnalytics
             * @instance
             * @return {Request} The current instance of the request so calls can be chained.
             */
            clearAnalytics: function() {
                delete this.analytics;
                return this;
            },

            /**
             * @global
             * @typedef RunArguments
             * @type {Object}
             * @property {Object}  [analytics] Request analytics for this API call.
             * @property {Object}  args        Argument to the API call.
             * @property {String}  func        Name of the API call.
             * @property {Boolean} json        When true, send request as application/json, otherwise, send request as application/x-www-form-urlencoded
             * @property {Object}  meta        Filter, sort and paging rules for API call.
             * @property {String}  [module]    Name of the module where the API call exists. Required for UAPI. Optional for WHM API v1.
             * @property {Number}  [version]   Version of the API.
             */

            /**
             * Build the UAPI call data structure.
             *
             * @method getRunArguments
             * @instance
             * @return {RunArguments} Packages up an API call based on collected information.
             */
            getRunArguments: function() {
                return {
                    version: this.version,
                    module: this.module,
                    func: this.func,
                    meta: this.meta,
                    args: this.args,
                    analytics: this.analytics,
                    json: this.json
                };
            },

            /**
             * Validate that the args property is an object. Used by other methods that depend on this precondition.
             *
             * @protected
             * @param  {String} method Name of the method being attempted.
             * @throws When this.args is not an object.
             */
            validateArgs: function(method) {
                if (typeof this.args !== "object") {
                    throw new Error("You can not call '" + method + "'' if you the args property to something other than an Object");
                }
            },

            /**
             * Validate that the meta property is an object. Used by other methods that depend on this precondition.
             *
             * @protected
             * @param  {String} method Name of the method being attempted.
             * @throws When this.meta is not an object.
             */
            validateMeta: function(method) {
                if (typeof this.meta !== "object") {
                    throw new Error("You can not call '" + method + "'' if you the meta property to something other than an Object");
                }
            }
        };

        return Request;
    };
});
