/*
# api/io/uapi.js                                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* eslint-env amd */
/* eslint camelcase: "off" */
/* --------------------------*/

// TODO: Add tests for these

/**
 * Contain the IAPI Driver implementation used to process cpanel uapi
 * request/response messages.
 *
 * @module cjt2/io/uapi
 * @example
 *
 * require([
 *      "cjt/io/api",
 *      "cjt/io/uapi-request",
 *      "cjt/io/uapi", // IMPORTANT: Load the driver so its ready
 * ], function(API, APIREQUEST) {
 *     return {
 *         getUsers: function {
 *             var apiCall = new APIREQUEST.Class();
 *             apiCall.initialize(UserManager, "list_users");
 *             return API.promise(apiCall.getRunArguments());
 *         }
 *     };
 * });
 */
define([
    "lodash",
    "cjt/io/base",
    "cjt/util/test",
    "cjt/util/parse",
    "cjt/util/query"
], function(_, BASE, TEST, PARSE, QUERY) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/uapi"; // requirejs(["cjt/io/uapi"], function(api) {}); -> cjt/io/uapi.js || cjt/io/uapi.debug.js
    var MODULE_DESC = "Contains the unique bits for integration with UAPI calls.";
    var MODULE_VERSION = "2.0";

    // ------------------------------
    // Shortcuts
    // ------------------------------

    // Since UAPI doesn’t return the information on which API call
    // we called, we need to iterate through the response data and supply that.
    // Compare to whm-v1.js (cf. is_batch_response() in that module).
    function _expand_response_with_module_and_func(response, args_obj) {

        // This way we don’t alter anything that was passed in.
        var resp = _.assign({}, response);

        if ( args_obj.batch ) {

            resp.module = "Batch";

            // Possibly offer a "loose" mode in the API at some point?
            // That will prompt more logic to be created here.
            resp.func = "strict";

            if (Array.isArray(resp.data)) {

                // Unlike WHM API v1, UAPI batching allows nested batches.
                // It could be useful if we implement a “loose” batch method.
                resp.data = resp.data.map( function( di, idx ) {
                    return _expand_response_with_module_and_func( di, args_obj.batch[idx] );
                } );
            }
        } else {
            resp.module = args_obj.module;
            resp.func = args_obj.func;
        }

        return resp;
    }

    function _get_module(args_obj) {
        return ( args_obj.batch ? "Batch" : args_obj.module );
    }

    function _get_func(args_obj) {
        return ( args_obj.batch ? "strict" : args_obj.func );
    }

    /**
     * IAPIDriver for uapi
     *
     * @exports module:cjt/io/uapi:UapiDriver
     */
    var uapi = {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,

        /**
         * Parse a YUI asyncRequest response object to extract
         * the interesting parts of a cPanel UAPI call response.
         *
         * @static
         * @param {object} response The asyncRequest response object
         * @return {object} See api_base._parse_response for the format of this object.
         */
        parse_response: function(response, type, args_obj) {

            // BASE._parse_response does this for us, but we can’t
            // depend on that since we have to twiddle with the response
            // to expand any batches.
            response = JSON.parse(response);

            response = _expand_response_with_module_and_func(response, args_obj);

            return BASE._parse_response(uapi, response);
        },

        /**
         * Determine if the response is a batch
         *
         * @static
         * @param  {Object}  response
         * @return {Boolean}          true if this is a batch, false otherwise
         * @see module:cjt/io/whm-v1
         */
        is_batch_response: function(response) {

            // We might include other batch functions in here in the future.
            return ( (response.module === "Batch") && (response.func === "strict") );
        },

        /**
         * Return a list of messages from a cPanel UAPI response, normalized as a
         * list of [ { level:"info|warn|error", content:"..." }, ... ]
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {array} The messages that the API call returned
         */
        find_messages: function(response) {
            if (!response ) {
                return [{
                    level: "error",
                    content: BASE._unknown_error_msg()
                }];
            }

            if ("errors" in response ) {
                var err = response.errors;
                if ( err ) {
                    return [{
                        level: "error",
                        content: err.length ? _.escape(err.join("\n")) : BASE._unknown_error_msg()
                    }];
                }

            }
            if ("messages" in response) {
                var messages = response.messages;
                if ( messages ) {
                    return [{
                        level: "msg",
                        content: messages.length ? _.escape(messages.join("\n")) : BASE._unknown_error_msg()
                    }];
                }
            }

            return [];
        },

        /**
         * Indicates whether this module’s find_messages() function
         * HTML-escapes.
         */
        HTML_ESCAPES_MESSAGES: true,

        /**
         * Return what a cPanel UAPI call says about whether it succeeded or not
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {boolean} Whether the API call says it succeeded
         */
        find_status: function(response) {
            try {
                var status = false;
                if (response) {
                    if (typeof (response.status) !== "undefined") {
                        status = PARSE.parsePerlBoolean(response.status);
                    } else {
                        if (window.console) {
                            window.console.log("The response does not conform to UAPI standards: A status field is required.");
                        }
                    }
                }
                return status;
            } catch (e) {
                return false;
            }
        },

        /**
         * Return normalized data from a UAPI call
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {array} The data that the API returned
         */
        get_data: function(response) {
            return response.data;
        },


        /**
         * Return normalized data from a cPanel API 2 call
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {array} The data that the API returned
         */
        get_meta: function(response) {
            var meta = {
                paginate: {
                    is_paged: false,
                    total_records: 0,
                    current_record: 0,
                    total_pages: 0,
                    current_page: 0,
                    page_size: 0
                },
                filter: {
                    is_filtered: false,
                    records_before_filter: NaN,
                    records_filtered: NaN
                }
            };

            if (TEST.objectHasPath(response, "metadata.paginate")) {
                var paginate = meta.paginate;
                paginate.is_paged = true;
                paginate.total_records = response.metadata.paginate.total_results || paginate.total_records || 0;
                paginate.current_record = response.metadata.paginate.start_result || paginate.current_record || 0;
                paginate.total_pages = response.metadata.paginate.total_pages || paginate.total_pages || 0;
                paginate.current_page = response.metadata.paginate.current_page || paginate.current_page || 0;
                paginate.page_size = response.metadata.paginate.results_per_page || paginate.page_size || 0;
            }

            if (TEST.objectHasPath(response, "metadata.filter")) {
                meta.filter.is_filtered = true;
                meta.filter.records_before_filter = response.metadata.records_before_filter || 0;
            }

            // Copy any custom meta data properties.
            if (TEST.objectHasPath(response, "metadata")) {
                for (var key in response.metadata) {
                    if (response.metadata.hasOwnProperty(key) &&
                         (key !== "filter" && key !== "paginate")) {
                        meta[key] = response.metadata[key];
                    }
                }
            }

            return meta;
        },

        _assemble_batch: function(batch_list) {
            var commands = batch_list.map( function(b) {
                if (b.args) {
                    b = Object.create(b);
                    b.args = QUERY.expand_arrays_for_cpanel_api(b.args);
                }

                return JSON.stringify([
                    b.module,
                    b.func,
                    uapi.build_query(b),
                ]);
            } );

            return {
                command: commands
            };
        },

        /**
         * Build the call structure from the arguments and data.
         *
         * @static
         * @param  {Object} args_obj    Arguments passed to the call.
         * @return {Object}             Object representation of the call arguments
         */
        build_query: function(args_obj) {
            if (args_obj.batch) {
                return this._assemble_batch(args_obj.batch);
            }

            // Utility variables, used in specific contexts below.
            var s, cur_sort, f, cur_filter;

            var api_prefix = "api.";

            var api_call = {};
            if (args_obj.args) {
                _.extend(api_call, args_obj.args);
            }

            if (args_obj.meta) {
                if (args_obj.meta.sort) {

                    var sort_count = args_obj.meta.sort.length;
                    if (sort_count === 1) {
                        cur_sort = args_obj.meta.sort[0];
                        if (cur_sort instanceof Array) {
                            api_call[api_prefix + "sort_method"] = cur_sort[1];
                            cur_sort = cur_sort[0];
                        }
                        if (cur_sort.charAt(0) === "!") {
                            api_call[api_prefix + "sort_reverse"] = 1;
                            cur_sort = cur_sort.substr(1);
                        }
                        api_call[api_prefix + "sort_column"] = cur_sort;
                    } else {
                        for (s = 0; s < sort_count; s++) {
                            cur_sort = args_obj.meta.sort[s];
                            if (cur_sort instanceof Array) {
                                api_call[api_prefix + "sort_method_" + s] = cur_sort[1];
                                cur_sort = cur_sort[0];
                            }
                            if (cur_sort.charAt(0) === "!") {
                                api_call[api_prefix + "sort_reverse_" + s] = 1;
                                cur_sort = cur_sort.substr(1);
                            }
                            api_call[api_prefix + "sort_column_" + s] = cur_sort;
                        }
                    }
                }

                if (args_obj.meta.filter) {
                    var filter_count = args_obj.meta.filter.length;

                    if (filter_count === 1) {
                        cur_filter = args_obj.meta.filter[0];

                        api_call[api_prefix + "filter_column"] = cur_filter[0];
                        api_call[api_prefix + "filter_type"] = cur_filter[1];
                        api_call[api_prefix + "filter_term"] = cur_filter[2];
                    } else {
                        for (f = 0; f < filter_count; f++) {
                            cur_filter = args_obj.meta.filter[f];

                            api_call[api_prefix + "filter_column_" + f] = cur_filter[0];
                            api_call[api_prefix + "filter_type_" + f] = cur_filter[1];
                            api_call[api_prefix + "filter_term_" + f] = cur_filter[2];
                        }
                    }
                }

                if (args_obj.meta.paginate) {
                    if ("start" in args_obj.meta.paginate) {
                        api_call[api_prefix + "paginate_start"] = args_obj.meta.paginate.start;
                    }
                    if ("size" in args_obj.meta.paginate) {
                        api_call[api_prefix + "paginate_size"] = args_obj.meta.paginate.size;
                    }
                }
                delete args_obj.meta;
            }

            if (args_obj.analytics) {
                api_call[api_prefix + "analytics"] = args_obj.analytics.serialize();
            }

            return api_call;
        },

        /**
         * Assemble the url for the request.
         *
         * @static
         * @param  {String} token    cPanel Security Token
         * @param  {Object} args_obj Arguments passed to the call.
         * @return {String}          Url prefix for the call
         */
        get_url: function(token, args_obj ) {
            return token + [
                "",
                "execute",
                _get_module(args_obj),
                _get_func(args_obj),
            ].map(encodeURIComponent).join("/");
        }
    };

    return uapi;
});
