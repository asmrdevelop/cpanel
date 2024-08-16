/*
# whm-v1.js                                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:false*/
/* --------------------------*/

// TODO: Add tests for these

/**
 * Contain the IAPI Driver implementation used to process whm api1
 * request/response messages.
 *
 * @module cjt2/io/whm-v1
 * @example
 *
 * require([
 *      "cjt/io/api",
 *      "cjt/io/whm-v1-request",
 *      "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
 * ], function(API, APIREQUEST) {
 *     return {
 *         getLog: function {
 *             var apiCall = new APIREQUEST.Class();
 *             var NO_MODULE = "";
 *             apiCall.initialize(NO_MODULE, "modsec_get_log");
 *             return API.promise(apiCall.getRunArguments());
 *         }
 *     };
 * });
 *
 */
define([
    "lodash",
    "cjt/io/base",
    "cjt/util/query",
    "cjt/util/string",
    "cjt/util/test",
    "cjt/io/uapi"
], function(_, BASE, QUERY, STRING, TEST, UAPI) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/whm-v1"; // requirejs(["cjt/io/whm-v1"], function(api) {}); -> cjt/io/whm-v1.js || cjt/io/whm-v1.min.js
    var MODULE_DESC = "Contains the unique bits for integration with WHM v1 API calls.";
    var MODULE_VERSION = "2.0";

    var API_VERSION = 1;

    // ------------------------------
    // Shortcuts
    // ------------------------------

    // Here we work around some quirks of WHM API v1's "output" property:
    //  - convert "messages" and "warnings" from the API response
    //      to "info" and "warn" for consistency with the console object and
    //      Cpanel::Logger.
    //  - The list of messages is inconsistently given to the API caller among
    //      different API calls: modifyacct gives an array of messages, while
    //      sethostname joins the messages with a newline. We normalize in the
    //      direction of an array.
    var _message_label_conversion = [{
        server: "warnings",
        client: "warn"
    }, {
        server: "messages",
        client: "info"
    }];

    /**
     * Normalize the whm messages.
     * @method _normalizeMessages
     * @private
     * @param  {Object} response Response object
     * @return {Array} Array of objects as follows:
     *    [n].level
     *    [n].content
     * @throws {String} ???
     */
    var _normalizeMessages = function(response) {
        var messages = [];
        var output = response.metadata.output;
        if (output) {
            _message_label_conversion.forEach(function(xform) {
                var current_msgs = output[xform.server];
                if (current_msgs) {
                    if (typeof current_msgs === "string") {
                        current_msgs = current_msgs.split(/\n/);
                    }

                    if (typeof current_msgs === "object" && current_msgs instanceof Array) {
                        current_msgs.forEach(function(m) {
                            messages.push({
                                level: xform.client,
                                content: String(m)
                            });
                        });
                    } else {
                        throw xform.server + " is a " + (typeof current_msgs);
                    }
                }
            });
        }

        return messages;
    };

    /**
     * Convert from a number into a string that WHM API v1 will sort
     * in the same order as the numbers; e.g.: 26=>"za", 52=>"zza", ...
     * @method  _make_whm_api_fieldspec_from_number
     * @private
     * @param  {Number} num ???
     * @return {String}     ???
     */
    var _make_whm_api_fieldspec_from_number = function(num) {
        var left = STRING.lpad("", parseInt(num / 26, 10), "z");
        return left + "abcdefghijklmnopqrstuvwxyz".charAt(num % 26);
    };


    /**
     * WHM XML-API v1 usually puts list data into a single-key hash.
     * This isn't useful for us, so we get rid of the extra hash.
     *
     * @method _reduce_list_data
     * @private
     * @param {object} data The "data" member of the API JSON response
     * @return {object|array} The data that the API returned
     */
    var _reduce_list_data = function(data) {
        if ((typeof data === "object") && !(data instanceof Array)) {
            var keys = Object.keys(data);
            if (keys.length === 1) {
                var maybe_data = data[keys[0]];
                if (maybe_data) {
                    if (maybe_data instanceof Array) {
                        data = maybe_data;
                    }
                } else {
                    data = [];
                }
            }
        }

        return data;
    };

    var _getFunc = function(argsObj) {
        if (argsObj.batch) {
            return "batch";
        }

        return argsObj.func;
    };

    /**
     * IAPIDriver for WHM v1 API
     *
     * @exports module:cjt/io/whm-v1:WhmV1Driver
     */
    var whmV1 = {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,

        /**
         * Parse a YUI asyncRequest response object to extract
         * the interesting parts of a WHM API v1 call response.
         *
         * @static
         * @param {object} response The asyncRequest response object
         * @param {object} argsObj
         * @return {object} See BASE._parse_response for the format of this object.
         */
        parse_response: function(response, type, argsObj) {

            var iapiModule = whmV1;

            /*
             * If the special endpoint was cpanel and the cpanel_jsonapi_apiversion
             * was "3", parse the response using UAPI logic.
             */

            if (typeof (argsObj) === "object" && argsObj.func === "cpanel" && argsObj.args.hasOwnProperty("cpanel_jsonapi_apiversion") && parseInt(argsObj.args.cpanel_jsonapi_apiversion) === 3) {

                iapiModule = UAPI;

                try {
                    response = JSON.parse(response).result;
                } catch (e) {

                    // ignored
                }

                if (!_.isPlainObject(response)) {

                    // Response is not in a parsable format for UAPI
                    // Create a generic API failure response instead
                    response = {
                        "messages": null,
                        "errors": [
                            BASE._unknown_error_msg()
                        ],
                        "metadata": {},
                        "data": null,
                        "warnings": null,
                        "status": 0
                    };
                }
            }

            return BASE._parse_response( iapiModule, response);
        },

        /**
         * Return a list of messages from a WHM API v1 response, normalized as a
         * list of [ { level:"info|warn|error", content:"..." }, ... ]
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {array} The messages that the API call returned
         */
        find_messages: function(response) {
            if (!response || !response.metadata) {
                return [{
                    level: "error",
                    content: BASE._unknown_error_msg()
                }];
            }

            var msgs = _normalizeMessages(response);

            if (String(response.metadata.result) !== "1") {
                msgs.unshift({
                    level: "error",
                    content: response.metadata.reason || BASE._unknown_error_msg()
                });
            }

            return msgs;
        },

        /**
         * Indicates whether this module’s find_messages() function
         * HTML-escapes.
         */
        HTML_ESCAPES_MESSAGES: false,

        /**
         * Return what a WHM API v1 call says about whether it succeeded or not
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {boolean} Whether the API call says it succeeded
         */
        find_status: function(response) {
            try {
                var result = parseInt(response.metadata.result, 10) || 0;
                return result === 1;
            } catch (e) {}

            return false;
        },

        /**
         * Return normalized data from a WHM API v1 call
         * (See reduce_list_data for special processing of this API call.)
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {object|array} The data that the API returned
         */
        get_data: function(response) {
            var payload = _reduce_list_data(response.data);

            if (whmV1.is_batch_response(response)) {
                payload.forEach( function(p) {
                    p.data = _reduce_list_data(p.data);
                } );
            }

            return payload;
        },

        /**
         * Determine if the response is a batch
         *
         * Since the API response includes the function that was sent,
         * we can just look at that to determine if this was a batch call.
         * This is a “cheat”; it’d be a bit “purer” to look at the
         * actual API request to determine whether we should consider a
         * response to be a batch response, but since WHM API v1 gives us
         * that information in the response itself, using that seems like
         * an acceptable “shortcut”.
         *
         * For comparison, look at uapi.js to see the extra logic that we have
         * to go through to get the same information from the request. It’s
         * a bit better that way in that if, for some reason, the server were
         * to respond to a batch request with a non-batch response (or
         * vice-versa), we’ll get a more useful error--but that’s pretty
         * unlikely, and we’ll likely detect it quickly enough regardless.
         *
         * @static
         * @param  {Object}  response
         * @return {Boolean}          true if this is a batch, false otherwise
         * @see module:cjt/io/whm-v1
         */
        is_batch_response: function(response) {
            return ( response.metadata.command === "batch" );
        },

        /**
         * Return normalized meta data from a WHM API v1 call
         *
         * @static
         * @param {object} response The parsed API JSON response
         * @return {object} The meta data that the API returned after
         * transformation.
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

            if (TEST.objectHasPath(response, "metadata.chunk")) {
                var paginate = meta.paginate;
                paginate.is_paged = true;
                paginate.total_records = response.metadata.chunk.records || 0;
                paginate.current_record = response.metadata.chunk.start || 0;
                paginate.total_pages = response.metadata.chunk.chunks || 0;
                paginate.current_page = response.metadata.chunk.current || 0;
                paginate.page_size = response.metadata.chunk.size || 0;
                meta.paginate = paginate;
            }

            if (TEST.objectHasPath(response, "metadata.filter")) {
                meta.filter.is_filtered = true;

                // TODO: Add support to api to return before filtering #
                // meta.filter.records_before_filter = response.metadata.filter.??? || 0;
                meta.filter.records_filtered = response.metadata.filter.filtered || 0;
                if (response.metadata.filter.filtered) {
                    delete response.metadata.filter.filtered;
                }
                meta.filter.filters = response.metadata.filter;
            }

            // Copy any custom meta data properties.
            if (TEST.objectHasPath(response, "metadata")) {
                for (var key in response.metadata) {
                    if (response.metadata.hasOwnProperty(key) &&
                        (key !== "filter" && key !== "chunk")) {
                        meta[key] = response.metadata[key];
                    }
                }
            }

            return meta;
        },

        _assemble_batch: function(batchList) {
            var commands = batchList.map( function(b) {
                var q = whmV1.build_query(b);
                return encodeURIComponent(_getFunc(b)) + "?" + QUERY.make_query_string(q);
            } );

            return {
                "api.version": API_VERSION,
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
            var s, cur_sort, f, cur_filter, prefix;

            var api_call = {};
            if (args_obj.args) {
                _.extend(api_call, args_obj.args);
            }

            api_call["api.version"] = API_VERSION;

            if (args_obj.meta) {
                var sorts = args_obj.meta.sort;
                var filters = args_obj.meta.filter;
                var paginate = args_obj.meta.paginate;

                if (sorts && sorts.length) {
                    api_call["api.sort.enable"] = 1;
                    for (s = sorts.length - 1; s >= 0; s--) {
                        cur_sort = sorts[s];
                        prefix = "api.sort." + _make_whm_api_fieldspec_from_number(s);
                        if (cur_sort instanceof Array) {
                            api_call[prefix + ".method"] = cur_sort[1];
                            cur_sort = cur_sort[0];
                        }
                        if (cur_sort.charAt(0) === "!") {
                            api_call[prefix + ".reverse"] = 1;
                            cur_sort = cur_sort.substr(1);
                        }
                        api_call[prefix + ".field"] = cur_sort;
                    }
                }

                if (filters && filters.length) {
                    api_call["api.filter.enable"] = 1;
                    api_call["api.filter.verbose"] = 1;

                    for (f = filters.length - 1; f >= 0; f--) {
                        cur_filter = filters[f];
                        prefix = "api.filter." + _make_whm_api_fieldspec_from_number(f);

                        api_call[prefix + ".field"] = cur_filter[0];
                        api_call[prefix + ".type"]  = cur_filter[1];
                        api_call[prefix + ".arg0"]  = cur_filter[2];
                    }
                }

                if (paginate && paginate.enabled) {
                    api_call["api.chunk.enable"]  = 1;
                    api_call["api.chunk.verbose"] = 1;

                    if ("start_record" in paginate) {
                        api_call["api.chunk.start"] = paginate.start_record;
                    }
                    if ("page_size" in paginate) {
                        api_call["api.chunk.size"] = paginate.page_size;
                    }
                }
            }

            return api_call;
        },

        /**
         * Assemble the url for the request. Since WHM API1 doesn't actually provide any
         * modularization of the API methods and consists of a list of function names, this
         * method provides an unenforced way to provide some makeshift modularity by
         * creating a prefix from args_obj.module for the API call. This also allows WHM
         * API1 calls to be made in the same manner as UAPI calls.
         *
         * @static
         * @param  {String} token    cPanel Security Token
         * @param  {Object} args_obj Arguments passed to the call.
         * @return {String}          Url prefix for the call
         */
        get_url: function(token, argsObj) {
            var modulePrefix = argsObj.module ? argsObj.module.toLowerCase() + "_" : "";
            return token + "/json-api/" + encodeURIComponent(modulePrefix + _getFunc(argsObj));
        }
    };

    return whmV1;

});
