/*
# api/io/api2.js                                     Copyright 2022 cPanel, L.L.C.
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
 * Contain the IAPI Driver implementation used to process cpanel api2
 * request/response messages.
 * @module cjt2/io/api2
 * @example
 *
 */
define(["lodash", "cjt/io/base", "cjt/util/test"], function(_, BASE, TEST) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/io/api2"; // requirejs(["cjt/io/api2"], function(api) {}); -> cjt/io/api2.js || cjt/io/api2.debug.js
    var MODULE_DESC = "Contains the unique bits for integration with API2 calls.";
    var MODULE_VERSION = "2.0";

    var API_VERSION = 2;

    // ------------------------------
    // Shortcuts
    // ------------------------------

    /**
     * IAPIDriver for API2
     *
     * @static
     * @public
     * @class API2
     */
    var api2 = {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,

        /**
         * Parse an api2-request object to extract
         * the interesting parts of a cPanel API 2 call response.
         *
         * @method parse_response
         * @param {object} response The asyncRequest response object
         * @return {object} See api_base._parse_response for the format of this object.
         */
        parse_response: function(response) {
            return BASE._parse_response(api2, response);
        },

        /**
         * Return a list of messages from a cPanel API 2 response, normalized as a
         * list of [ { level:"info|warn|error", content:"..." }, ... ]
         *
         * @method find_messages
         * @param {object} response The parsed API JSON response
         * @return {array} The messages that the API call returned
         */
        find_messages: function(response) {
            if (!response || !response.cpanelresult) {
                return [{
                    level: "error",
                    content: BASE._unknown_error_msg()
                }];
            }

            if ("error" in response.cpanelresult) {
                var err = response.cpanelresult.error;
                return [{
                    level: "error",
                    content: err ? _.escape(err) : BASE._unknown_error_msg()
                }];
            }

            // Some apis (e.g. ZoneEdit::fetchzone) return an error as part of the data in the first data argument
            // another api (ZoneEdit::remove_zone_record) returns an error as part of a result object in the data object
            // NOTE: This doesn't account for the actual status that is returned, it just grabs whatever message is there.
            // We are depending on the callers of the api call to check the status before displaying any messages found.
            if (response.cpanelresult.data &&
                response.cpanelresult.data[0]) {
                var msg;
                if (response.cpanelresult.data[0].hasOwnProperty("statusmsg")) {
                    msg = response.cpanelresult.data[0].statusmsg;
                } else if (response.cpanelresult.data[0].hasOwnProperty("result") &&
                    response.cpanelresult.data[0].result.hasOwnProperty("statusmsg")) {
                    msg = response.cpanelresult.data[0].result.statusmsg;
                }

                if (msg) {
                    return [{
                        level: "error",
                        content: msg ? _.escape(msg) : BASE._unknown_error_msg()
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
         * Return what a cPanel API 2 call says about whether it succeeded or not
         *
         * @method find_status
         * @param {object} response The parsed API JSON response
         * @return {boolean} Whether the API call says it succeeded
         */
        find_status: function(response) {
            try {
                var status = false;
                if (response && response.cpanelresult) {
                    var result = response.cpanelresult;
                    if (result.event && result.event.result) {

                        // We prefer to use this method, but some older api's may not correctly return this yet
                        // or under certain exceptional conditions, this may not be correctly filled.
                        status = (response.cpanelresult.event.result === 1);

                        if (status && result.error) {

                            // Some apis are really bad and return success and an error which should be an error.
                            status = false;
                        }

                        // Some apis (e.g. ZoneEdit::fetchzone) return an error as part of the data in the first data argument
                        // another api (ZoneEdit::remove_zone_record) returns an error as part of a result object in the data object
                        if (result.data &&
                            result.data[0]) {
                            if (result.data[0].hasOwnProperty("status")) {
                                status = result.data[0].status;
                            } else if (result.data[0].hasOwnProperty("result") &&
                                result.data[0].result.hasOwnProperty("status")) {
                                status = result.data[0].result.status;
                            }
                        }

                    } else {

                        // In the case of apis that don't quite comply with the API2 layout or ones that
                        // can fail without returning the event container above, we have this as a fallback
                        // to detecting an error.
                        status = !result.error;
                    }
                }
                return status;
            } catch (e) {
                return false;
            }
        },

        /**
         * Return normalized data from a cPanel API 2 call
         *
         * @method get_data
         * @param {object} response The parsed API JSON response
         * @return {array} The data that the API returned
         */
        get_data: function(response) {
            return response.cpanelresult.data;
        },


        /**
         * Return normalized data from a cPanel API 2 call
         *
         * @method get_meta
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

            if (TEST.objectHasPath(response, "cpanelresult.paginate")) {
                var paginate = meta.paginate;
                paginate.is_paged = true;
                paginate.total_records = response.cpanelresult.paginate.total_results || paginate.total_results || 0;
                paginate.current_record = response.cpanelresult.paginate.start_result || paginate.start_result || 0;
                paginate.total_pages = response.cpanelresult.paginate.total_pages || paginate.total_pages || 0;
                paginate.current_page = response.cpanelresult.paginate.current_page || paginate.current_page || 0;
                paginate.page_size = response.cpanelresult.paginate.results_per_page || paginate.results_per_page || 0;
            }

            /**
             * @todo API2 returns the filter data as part of the main object, not inside of a "filter" key.
             * It's ok though, since we catch that field in the loop over the "custom" metadata properties.
             * So this code is not used from what I can tell.
             */
            if (TEST.objectHasPath(response, "cpanelresult.filter")) {
                meta.filter.is_filtered = true;
                meta.filter.records_before_filter = response.cpanelresult.records_before_filter || 0;
            }

            // Copy any custom meta data properties.
            if (TEST.objectHasPath(response, "cpanelresult")) {
                for (var key in response.cpanelresult) {
                    if (response.cpanelresult.hasOwnProperty(key) &&
                        ( key !== "filter" && key !== "paginate")) {
                        meta[key] = response.cpanelresult[key];
                    }
                }
            }

            return meta;
        },

        /**
         * Build the call structure from the arguments and data.
         *
         * @method build_query
         * @param  {Object} args_obj    Arguments passed to the call.
         * @return {Object}             Object representation of the call arguments
         */
        build_query: function(args_obj) {

            // Utility variables, used in specific contexts below.
            var s, cur_sort, f, cur_filter;

            var api_prefix = "api2_";
            var api_call = {
                cpanel_jsonapi_apiversion: API_VERSION,
                cpanel_jsonapi_module: args_obj.module,
                cpanel_jsonapi_func: args_obj.func
            };

            if (args_obj.args) {
                _.extend(api_call, args_obj.args);
            }

            if (args_obj.meta) {
                if (args_obj.meta.sort) {
                    var sort_count = args_obj.meta.sort.length;

                    if (sort_count) {
                        api_call.api2_sort = 1;
                    }

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

                    if (filter_count) {
                        api_call.api2_filter = 1;
                    }

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
                    api_call.api2_paginate = 1;
                    if ("start" in args_obj.meta.paginate) {
                        api_call[api_prefix + "paginate_start"] = args_obj.meta.paginate.start;
                    }
                    if ("size" in args_obj.meta.paginate) {
                        api_call[api_prefix + "paginate_size"] = args_obj.meta.paginate.size;
                    }
                }
                delete args_obj.meta;
            }

            return api_call;
        },

        /**
         * Assemble the url for the request.
         *
         * @method get_url
         * @param  {String} token    cPanel Security Token
         * @param  {Object} args_obj Arguments passed to the call.
         * @return {String}          Url prefix for the call
         */
        get_url: function(token) {
            return token + "/json-api/cpanel";
        }
    };

    return api2;
});
