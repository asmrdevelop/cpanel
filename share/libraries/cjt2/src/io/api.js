/*
# cjt/io/api.js                                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true, require:true, console: true */
/* --------------------------*/

/**
 *
 * @module cjt/io/api
 * @example
 *
 * require(["cjt/io/api"], function(API) {
 *      return API.promise({
 *          module: "SetLang",
 *          func:   "setlocale",
 *          data: { locale: "en-US" },
 *          callback: {
 *              failure: function(tId, res, args) {
 *                  // We only get here for api failures
 *
 *                  // Do something for failure
 *                  var error = String(res.error || res.cpanel_error || res);
 *                  if (!error) {
 *                  }
 *              },
 *              success: function(tId, res, args) {
 *                  // Do something for success
 *              }
 *          }
 *      } );
 */

/* eslint-disable */
define([
        "cjt/core",
        "jquery",
        "cjt/util/query",
        "cjt/util/locale"
    ],
    function(CJT, $, QUERY, LOCALE) {

        "use strict";

        //------------------------------
        // Module
        //------------------------------
        var MODULE_NAME = "cjt/io/api"; // requirejs(["cjt/io/api"], function(api) {}); -> cjt/io/api.js || cjt/io/api.debug.js
        var MODULE_DESC = "";
        var MODULE_VERSION = 2.0;

        /* Each API is implemented in a module that constructs a static object with the
           following interface.  Implementers must provide a complete set of these methods
           on their API driver object for it to function in the API system.

        var IAPIDriver = {
            parse_response : function(resp) {
            },
            find_messages : function(resp) {
            },
            find_status : function(resp) {
            },
            get_data : function(resp) {
            },
            get_meta : function(resp) {
            },
            build_query : function(api_version, args_obj) {
            },
            get_url : function(token, args_obj) {
            }
        }
        */


        /**
         * Wrapper method to make localization to an alternative AJAX model a bit more
         * transparent.
         *
         * @method  _ajax
         * @private
         * @param  {String} method  POST or GET
         * @param  {String} url     The url for the request
         * @param  {Object} args    The arguments object to pass to the api call.
         * @param  {Function} filter
         * @param  {Boolean} json   If true, send application/json as the Content-Type
         * @return {Promise}        A Promise object that when resolved indicates the api was run,
         *                          and when rejected indicates the api was not run or failed.
         */
        var _ajax = function(method, url, args, filter, json) {
            // Setting traditional to true so query params will look like:
            // field=value1&field=value2
            // instead of:
            // field[]=value1&field[]=value2
            var ajaxArgs = {
                type: method || "POST",
                url: url,
                data: args,
                traditional: true
            };

            if (filter) {
                ajaxArgs.dataFilter = filter;
                ajaxArgs.converters = {
                    "text json": function(data) {
                        // Replace the internal converter so we dont double parse.
                        return data;
                    }
                };
            }

            if (json) {
                ajaxArgs.contentType = "application/json";
            }

            return $.ajax(ajaxArgs);
        };

        /**
         * Normalized the application detection
         *
         * @method _find_is_whm
         * @private
         * @param  {Object} args_obj Arguments to the api call.
         *             {String} args_obj.application Optional name of the application.
         * @return {Boolean}
         */
        var _find_is_whm = function(args_obj) {
            return (
                args_obj.application === CJT.KNOWN_APPLICATIONS.WHM
                || CJT.isWhm()
                || CJT.isUnitTest() && require("karmaHelpers").isWhmUnitTest()
            );
        };

        /**
         * Normalized the version information for the application.
         *
         * @name _find_api_version
         * @private
         * @param  {Object} args_obj Arguments to the api call.
         * @return {Number}          Version number of the invoked api call.
         */
        var _find_api_version = function(args_obj) {
            var version;
            if ("version" in args_obj) {
                version = args_obj.version;
            } else if ("api_data" in args_obj &&
                "version" in args_obj.api_data) {
                version = args_obj.api_data.version;
            } else {
                // Since we didn't pass it, we have to guess
                if (_find_is_whm(args_obj)) {
                    // We are in WHM so default to WHM v1.
                    version = 1;
                } else {
                    // We are in CPANEL so default to API2.
                    // CONSIDER: This assumption will have to be evaluated once UAPI is
                    // more widely implemented at which time this would be change to 3.
                    version = 2;
                }
            }
            return parseInt(version, 10);
        };

        /**
         * Retrieves the driver for the specified interface and version
         *
         * @method  _get_api_driver
         * @private
         * @param  {Boolean} is_whm      true if we are in WHM, false otherwise.
         * @param  {Number}  api_version Version of the api: Should be 1, 2 or 3.
         * @return {Object}              Driver object for the requested interface and version supporting the IAPIDriver interface.
         */
        var _get_api_driver = function(is_whm, api_version) {
            var api_driver;
            if (is_whm) {
                switch (api_version) {
                case 1:
                    api_driver = require("cjt/io/whm-v1");
                    break;
                case 3:
                    // NOTE: This is future proofing, but not actually supported until UAPI is ported to WHM.
                    api_driver = require("cjt/io/uapi");
                    break;
                default:
                    // WHM defaults to WHM v1
                    api_driver = require("cjt/io/whm-v1");
                    break;
                }
            } else {
                switch (api_version) {
                case 1:
                    api_driver = require("cjt/io/api1");
                    break;
                case 2:
                    api_driver = require("cjt/io/api2");
                    break;
                case 3:
                    api_driver = require("cjt/io/uapi");
                    break;
                default:
                    // CPANEL defaults to API2
                    api_driver = require("cjt/io/api2");
                    break;
                }
            }
            return api_driver;
        };

        /**
         * Construct the api call query string
         *
         * @method construct_api_query
         * @private
         * @param  {Number} api_version Version number
         * @param  {Object} args_obj    Arguments to the call.
         * @param  {Object} driver      Driver supporting the IAPIDriver interface.
         * @return {String}             Url to call the api call.
         */
        var _construct_api_query = function(args_obj, driver) {
            var api_call = driver.build_query(args_obj);

            if (args_obj.json){
                return JSON.stringify(api_call);
            }

            // TODO: See if we can use Y.QueryString.stringify() here.
            return QUERY.make_query_string(api_call);
        };

        /**
         * Build the data filter from the driver.
         *
         * @method _build_data_filter
         * @private
         * @param  {Number} api_version Version of the api: Should be 1, 2 or 3.
         * @param  {Object} args_obj    Arguments to the call.
         * @param  {Object} driver      Driver supporting the IAPIDriver interface.
         * @return {Object}             Object containing the callbacks for the call
         * adjusted into a standard format.
         */
        var _build_data_filter = function(api_version, args_obj, driver) {

            var dataFilter = function(data, type) {
                var parse_response = driver.parse_response;
                if (!parse_response) {
                    var msg = "No parser for the API version requested:" + CJT.applicationName + " " + api_version;
                    console.log(msg, "error", MODULE_NAME);
                    throw msg;
                }

                return parse_response(data, type, args_obj);
            };

            return dataFilter;
        };

        //CPANEL.api()
        //
        //Normalize interactions with cPanel and WHM's APIs.
        //
        //This checks for API failures as well as HTTP failures; both are
        //routed to the "failure" callback.
        //
        //"failure" callbacks receive the same argument as with YUI
        //asyncRequest, but with additional properties as given in api_base._parse_response below.
        //
        //NOTE: WHM API v1 responses are normalized to a list if the API return
        //is a hash with only 1 value, and that value is a list.
        //
        //
        //This function takes a single object as its argument with these keys:
        //  module  (not needed in WHM API v1)
        //  func
        //  callback (cf. YUI 2 asyncRequest)
        //  data (goes to the API call itself)
        //  api_data (see below)
        //
        //Sort, filter, and pagination are passed in as api_data.
        //They are formatted thus:
        //
        //sort: [ "foo", "!bar", ["baz","numeric"] ]
        //  "foo" is sorted normally, "bar" is descending, then "baz" with method "numeric"
        //  NB: "normally" means that the API determines the sort method to use.
        //
        //filter: [ ["foo","contains","whatsit"], ["baz","gt",2], ["*","contains","bar"]
        //  each [] is column,type,term
        //  column of "*" is a wild-card search (only does "contains")
        //
        //paginate: { start: 12, size: 20 }
        //  gets 20 records starting at index 12 (0-indexed)
        //
        //NOTE: sorting, filtering, and paginating do NOT work with cPanel API 1!

        var api = {
            MODULE_NAME: MODULE_NAME,
            MODULE_DESC: MODULE_DESC,
            MODULE_VERSION: MODULE_VERSION,

            /**
             * Setup the api call promise
             *
             * @method promise
             * @static
             * @param  {Object} args_obj Object containing the arguments for the call
             * @return {Promise} A promise that encapsulates the request.
             */
            promise: function(args_obj) {
                if(typeof args_obj === "undefined"){
                    throw new Error("Parameter args_obj does not exist.");
                }
                var is_whm = _find_is_whm(args_obj);
                var api_version = _find_api_version(args_obj);

                // Retrieve the driver for the selected api
                var api_driver = _get_api_driver(is_whm, api_version);

                if (!api_driver) {
                    var msg = "Could not find the driver for the API version requested:" + CJT.applicationName + " " + api_version;
                    throw msg;
                }

                // Fix up the filter callback
                var filter = _build_data_filter(api_version, args_obj, api_driver);

                // Get the url from the driver
                var url = api_driver.get_url(CJT.securityToken, args_obj);

                var query = _construct_api_query(args_obj, api_driver);

                var method = (args_obj.args && typeof args_obj.args.method !== "undefined") ? args_obj.args.method : "POST";

                // Start the request
                var req_obj = _ajax(
                    method,
                    url,
                    query,
                    filter,
                    args_obj.json
                );

                return req_obj;
            }
        };

        return api;
    }
);
/* eslint-enable */
