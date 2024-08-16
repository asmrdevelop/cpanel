/*
# cpanel - base/cjt/api.js                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-disable camelcase */

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var CPANEL = window.CPANEL;
    var LOCALE = window.LOCALE;

    var DEFAULT_API_VERSION_CPANEL = 2;
    var DEFAULT_API_VERSION_WHM = 1;

    var _transaction_args = {};
    var _async_request = function() {
        var conn = YAHOO.util.Connect.asyncRequest.apply(YAHOO.util.Connect, arguments);
        if (conn && ("tId" in conn)) {
            _transaction_args[conn.tId] = arguments;
        }
        return conn;
    };

    // Convert from a number into a string that WHM API v1 will sort
    // in the same order as the numbers; e.g.: 26=>"za", 52=>"zza", ...
    var _make_whm_api_fieldspec_from_number = function(num) {
        var left = "".lpad(parseInt(num / 26, 10), "z");
        return left + "abcdefghijklmnopqrstuvwxyz".charAt(num % 26);
    };

    var _find_is_whm = function(args_obj) {
        return args_obj && (args_obj.application === "whm") || CPANEL.is_whm();
    };

    /**
     * Identify the API version that an API call object indicates.
     * This includes fallback to default API versions if the call object
     * doesn’t specify an API call.
     *
     * @method find_api_version
     * @static
     * @param args_obj {Object} The API call object
     * @return {Number} The default API version, as a number primitive
     */
    var find_api_version = function(args_obj) {
        var version;

        if (args_obj && "version" in args_obj) {
            version = args_obj.version;
        } else if (args_obj && args_obj.api_data && ("version" in args_obj.api_data)) {
            version = args_obj.api_data.version;
        } else if (_find_is_whm(args_obj)) {
            version = DEFAULT_API_VERSION_WHM;
        } else {
            version = DEFAULT_API_VERSION_CPANEL;
        }

        version = parseInt(version, 10);

        if (isNaN(version)) {
            throw "Invalid API version: " + args_obj.version;
        }

        return version;
    };

    // CPANEL.api()
    //
    // Normalize interactions with cPanel and WHM's APIs.
    //
    // This checks for API failures as well as HTTP failures; both are
    // routed to the "failure" callback.
    //
    // "failure" callbacks receive the same argument as with YUI
    // asyncRequest, but with additional properties as given in _parse_response below.
    //
    // NOTE: WHM API v1 responses are normalized to a list if the API return
    // is a hash with only 1 value, and that value is a list.
    //
    //
    // This function takes a single object as its argument with these keys:
    //  module  (not needed in WHM API v1)
    //  func
    //  callback (cf. YUI 2 asyncRequest)
    //  data (goes to the API call itself)
    //  api_data (see below)
    //
    // Sort, filter, and pagination are passed in as api_data.
    // They are formatted thus:
    //
    // sort: [ "foo", "!bar", ["baz","numeric"] ]
    //  "foo" is sorted normally, "bar" is descending, then "baz" with method "numeric"
    //  NB: "normally" means that the API determines the sort method to use.
    //
    // filter: [ ["foo","contains","whatsit"], ["baz","gt",2], ["*","contains","bar"]
    //  each [] is column,type,term
    //  column of "*" is a wildcard search (only does "contains")
    //
    // paginate: { start: 12, size: 20 }
    //  gets 20 records starting at index 12 (0-indexed)
    //
    // analytics: { enabled: true }
    //
    // NOTE: analytics, sorting, filtering, and paginating do NOT work with cPanel API 1!
    var api = function(args_obj) {
        var callback;
        var req_obj;
        if (typeof args_obj.callback === "function") {
            callback = {
                success: args_obj.callback
            };
        } else if (args_obj.callback) {
            callback = YAHOO.lang.augmentObject({}, args_obj.callback);
        } else {
            callback = {};
        }

        var pp_opts = args_obj.progress_panel;
        var pp; // the Progress_Panel instance
        if (pp_opts) {
            if (!CPANEL.ajax.build_callback) {
                throw "Need CPANEL.ajax!";
            }

            pp = new CPANEL.ajax.Progress_Panel(pp_opts);
            var source_el = pp_opts.source_el;
            if (source_el) {
                pp.show_from_source(source_el);
            } else {
                pp.cfg.setProperty("effect", CPANEL.ajax.FADE_MODAL);
                pp.show();
            }

            var before_pp_success = callback.success;
            var pp_callback = CPANEL.ajax.build_callback(
                function() {

                    // This gives us a means of interrupting the normal response to
                    // a successful return, e.g., if we want to display a warning
                    // about a partial success.
                    if (pp_opts.before_success && pp_opts.before_success.apply(pp, arguments) === false) {
                        return;
                    }

                    if (source_el) {
                        pp.hide_to_point(source_el);
                    } else {
                        pp.hide();
                    }

                    var notice_opts = pp_opts.success_notice_options || {};
                    YAHOO.lang.augmentObject(notice_opts, {
                        level: "success",
                        content: pp_opts.success_status || LOCALE.maketext("Success!")
                    });

                    req_obj.notice = new CPANEL.ajax.Dynamic_Notice(notice_opts);

                    if (before_pp_success) {
                        return before_pp_success.apply(this, arguments);
                    }
                }, {
                    current: pp
                }, {
                    keep_current_on_success: true,
                    on_error: pp_opts.on_error,
                    failure: callback.failure
                }
            );
            YAHOO.lang.augmentObject(callback, pp_callback, true);
        }

        var is_whm = _find_is_whm(args_obj);

        var api_version = find_api_version(args_obj);

        var given_success = callback.success;
        callback.success = function(o) {
            var parser = (is_whm ? _whm_parsers : _cpanel_parsers)[api_version];
            if (!parser) {
                throw "No parser for API version " + api_version;
            }

            YAHOO.lang.augmentObject(o, parser(o.responseText));

            if (!o.cpanel_status) {
                if (callback.failure) {
                    callback.failure.call(this, o);
                }
            } else {
                if (given_success) {
                    given_success.call(this, o);
                }
            }
        };

        req_obj = _async_request(
            "POST",
            construct_url_path(args_obj),  // eslint-disable-line no-use-before-define
            callback,
            construct_api_query(args_obj)  // eslint-disable-line no-use-before-define
        );

        if (pp) {
            req_obj.progress_panel = pp;
        }

        return req_obj;
    };

    /**
     * Returns the URL path for an API call
     *
     * @method construct_url_path
     * @static
     * @param args_obj {Object} The API query object.
     * @return {String} The path component of the URL for the API query.
     */
    var construct_url_path = function(args_obj) {
        var is_whm = _find_is_whm(args_obj);

        var api_version = find_api_version(args_obj);

        var url = CPANEL.security_token;
        if (is_whm) {
            if (!args_obj.batch && !args_obj.func) {
                return;
            }

            url += "/json-api/" + (args_obj.batch ? "batch" : encodeURIComponent(args_obj.func));
        } else {
            if (!args_obj.module || !args_obj.func) {
                return;
            }

            if (api_version === 3) {
                url += "/execute/" + encodeURIComponent(args_obj.module) + "/" + encodeURIComponent(args_obj.func);
            } else {
                url += "/json-api/cpanel";
            }
        }

        return url;
    };

    /**
     * It is useful for error reporting to show a failed transaction's arguments,
     * so CPANEL.api stores these internally for later reporting.
     *
     * @method get_transaction_args
     * @param {number} t_id The transaction ID (as given by YUI 2 asyncRequest)
     * @return {object} A copy of the "arguments" object
     */
    var get_transaction_args = function(t_id) {
        var args = _transaction_args[t_id];
        return args && YAHOO.lang.augmentObject({}, args); // shallow copy
    };

    // Returns a query string.
    var construct_api_query = function(args_obj) {
        return CPANEL.util.make_query_string(translate_api_query(args_obj));
    };

    // Returns an object that represents form data.
    var translate_api_query = function(args_obj) {
        var this_is_whm = CPANEL.is_whm();

        var api_version = find_api_version(args_obj);

        var api_call = {};

        // Utility variables, used in specific contexts below.
        var s, cur_sort, f, cur_filter, prefix;

        // If WHM
        if ((args_obj.application === "whm") || this_is_whm) {
            api_call["api.version"] = api_version;

            if ("batch" in args_obj) {
                var commands = args_obj.batch.map(function(cmd) {
                    var safe_cmd = Object.create(cmd);
                    safe_cmd.version = api_version;

                    var query = translate_api_query(safe_cmd);
                    delete query["api.version"];

                    query = CPANEL.util.make_query_string(query);

                    return encodeURIComponent(safe_cmd.func) + (query && ("?" + query));
                });

                api_call.command = commands;

                if (args_obj.batch_data) {
                    YAHOO.lang.augmentObject(api_call, args_obj.batch_data);
                }
            } else {
                if (args_obj.data) {
                    YAHOO.lang.augmentObject(api_call, args_obj.data);
                }

                if (args_obj.api_data) {
                    var sorts = args_obj.api_data.sort;
                    var filters = args_obj.api_data.filter;
                    var paginate = args_obj.api_data.paginate;
                    var columns = args_obj.api_data.columns;
                    var analytics = args_obj.api_data.analytics;

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
                            api_call[prefix + ".type"] = cur_filter[1];
                            api_call[prefix + ".arg0"] = cur_filter[2];
                        }
                    }

                    if (paginate) {
                        api_call["api.chunk.enable"] = 1;
                        api_call["api.chunk.verbose"] = 1;

                        if ("start" in paginate) {
                            api_call["api.chunk.start"] = paginate.start + 1;
                        }
                        if ("size" in paginate) {
                            api_call["api.chunk.size"] = paginate.size;
                        }
                    }

                    if (columns) {
                        api_call["api.columns.enable"] = 1;
                        for (var c = 0; c < columns.length; c++) {
                            api_call["api.columns." + _make_whm_api_fieldspec_from_number(c)] = columns[c];
                        }
                    }

                    if (analytics) {
                        api_call["api.analytics"] = JSON.stringify(analytics);
                    }
                }
            }
        } else if (api_version === 2 || api_version === 3) { // IF cPanel Api2 or UAPI
            var api_prefix;

            if (api_version === 2) {
                api_prefix = "api2_";
                api_call.cpanel_jsonapi_apiversion = api_version;
                api_call.cpanel_jsonapi_module = args_obj.module;
                api_call.cpanel_jsonapi_func = args_obj.func;
            } else {
                api_prefix = "api.";
            }

            if (args_obj.data) {
                YAHOO.lang.augmentObject(api_call, args_obj.data);
            }
            if (args_obj.api_data) {
                if (args_obj.api_data.sort) {
                    var sort_count = args_obj.api_data.sort.length;

                    if (sort_count && (api_version === 2)) {
                        api_call.api2_sort = 1;
                    }

                    for (s = 0; s < sort_count; s++) {
                        cur_sort = args_obj.api_data.sort[s];
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

                if (args_obj.api_data.filter) {
                    var filter_count = args_obj.api_data.filter.length;

                    if (filter_count && (api_version === 2)) {
                        api_call.api2_filter = 1;
                    }

                    for (f = 0; f < filter_count; f++) {
                        cur_filter = args_obj.api_data.filter[f];

                        api_call[api_prefix + "filter_column_" + f] = cur_filter[0];
                        api_call[api_prefix + "filter_type_" + f] = cur_filter[1];
                        api_call[api_prefix + "filter_term_" + f] = cur_filter[2];
                    }
                }

                if (args_obj.api_data.paginate) {
                    if (api_version === 2) {
                        api_call.api2_paginate = 1;
                    }
                    if ("start" in args_obj.api_data.paginate) {
                        api_call[api_prefix + "paginate_start"] = args_obj.api_data.paginate.start + 1;
                    }
                    if ("size" in args_obj.api_data.paginate) {
                        api_call[api_prefix + "paginate_size"] = args_obj.api_data.paginate.size;
                    }
                }

                if (args_obj.api_data.columns) {
                    var columns_count = args_obj.api_data.columns.length;

                    if (columns_count && (api_version === 2)) {
                        api_call.api2_columns = 1;
                    }

                    for (var col = 0; col < columns_count; col++) {
                        api_call[api_prefix + "columns_" + col] = args_obj.api_data.columns[col];
                    }
                }

                if (args_obj.api_data.analytics) {
                    api_call[api_prefix + "analytics"] = JSON.stringify(args_obj.api_data.analytics);
                }
            }
        } else if (api_version === 1) {

            // for cPanel API 1, data is just a list
            api_call.cpanel_jsonapi_apiversion = 1;
            api_call.cpanel_jsonapi_module = args_obj.module;
            api_call.cpanel_jsonapi_func = args_obj.func;

            if (args_obj.data) {
                for (var d = 0; d < args_obj.data.length; d++) {
                    api_call["arg-" + d] = args_obj.data[d];
                }
            }
        }

        return api_call;
    };


    var _unknown_error_msg = function() {
        return LOCALE.maketext("An unknown error occurred.");
    };

    /**
     * Return normalized data from a WHM API v1 call
     * (See reduce_whm1_list_data for special processing of this API call.)
     *
     * @method _get_whm1_data
     * @private
     * @param {object} resp The parsed API JSON response
     * @return {object|array} The data that the API returned
     */
    var _get_whm1_data = function(resp) {
        var metadata = resp.metadata;
        var data_for_caller = resp.data;

        if (!metadata || !metadata.payload_is_literal || (metadata.payload_is_literal === "0")) {
            data_for_caller = reduce_whm1_list_data(data_for_caller);
        }

        if (metadata && (metadata.command === "batch")) {
            return data_for_caller.map(parse_whm1_response);
        }

        return data_for_caller;
    };

    /**
     * WHM XML-API v1 usually puts list data into a single-key hash.
     * This isn't useful for us, so we get rid of the extra hash.
     *
     * @method reduce_whm1_list_data
     * @param {object} data The "data" member of the API JSON response
     * @return {object|array} The data that the API returned
     */
    var reduce_whm1_list_data = function(data) {
        if (data && (typeof data === "object") && !(data instanceof Array)) {
            var keys = Object.keys(data);
            if (keys.length === 1) {
                var maybe_data = data[keys[0]];
                if (maybe_data && (maybe_data instanceof Array)) {
                    data = maybe_data;
                }
            }
        }

        return data;
    };

    /**
     * Return normalized data from a cPanel API 1 call
     *
     * @method _get_cpanel1_data
     * @private
     * @param {object} resp The parsed API JSON response
     * @return {string} The data that the API returned
     */
    var _get_cpanel1_data = function(resp) {
        try {
            return resp.data.result;
        } catch (e) {
            return;
        }
    };

    /**
     * Return normalized data from a cPanel API 2 call
     *
     * @method _get_cpanel2_data
     * @private
     * @param {object} resp The parsed API JSON response
     * @return {array} The data that the API returned
     */
    var _get_cpanel2_data = function(resp) {
        return resp.cpanelresult.data;
    };

    /**
     * Return normalized data from a UAPI call
     *
     * @method _get_uapi_data
     * @private
     * @param {object} resp The parsed API JSON response
     * @return {array} The data that the API returned
     */
    var _get_uapi_data = function(resp) {
        return resp.data;
    };

    /**
     * Return what a cPanel API 1 call says about whether it succeeded or not
     *
     * @method find_cpanel1_status
     * @param {object} resp The parsed API JSON response
     * @return {boolean} Whether the API call says it succeeded
     */
    var find_cpanel1_status = function(resp) {
        try {
            return !!Number(resp.event.result);
        } catch (e) {
            return false;
        }
    };

    /**
     * Return what a cPanel API 2 call says about whether it succeeded or not
     *
     * @method find_cpanel2_status
     * @param {object} resp The parsed API JSON response
     * @return {boolean} Whether the API call says it succeeded
     */
    var find_cpanel2_status = function(resp) {
        try {

            // NOTE: resp.event.result is NOT reliable!
            // Case in point: MysqlFE::userdbprivs
            return !resp.cpanelresult.error;
        } catch (e) {
            return false;
        }
    };

    /**
     * Return what a WHM API v1 call says about whether it succeeded or not
     *
     * @method find_whm1_status
     * @param {object} resp The parsed API JSON response
     * @return {boolean} Whether the API call says it succeeded
     */
    var find_whm1_status = function(resp) {
        try {
            return resp.metadata.result == 1;
        } catch (e) {}

        return false;
    };

    /**
     * Return what a UAPI call says about whether it succeeded or not
     *
     * @method find_uapi_status
     * @param {object} resp The parsed API JSON response
     * @return {boolean} Whether the API call says it succeeded
     */
    var find_uapi_status = function(resp) {
        try {
            return resp.status == 1;
        } catch (e) {}

        return false;
    };

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
    var _normalize_whm1_messages = function(resp) {
        var messages = [];
        var output = resp.metadata.output;
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
     * Return a list of messages from a WHM API v1 response, normalized as a
     * list of [ { level:"info|warn|error", content:"..." }, ... ]
     *
     * @method find_whm1_messages
     * @param {object} resp The parsed API JSON response
     * @return {array} The messages that the API call returned
     */
    var find_whm1_messages = function(resp) {
        if (!resp || !resp.metadata) {
            return [{
                level: "error",
                content: _unknown_error_msg()
            }];
        }

        var msgs = _normalize_whm1_messages(resp);

        if (String(resp.metadata.result) !== "1") {
            msgs.unshift({
                level: "error",
                content: resp.metadata.reason || _unknown_error_msg()
            });
        }

        return msgs;
    };

    /**
     * Return a list of messages from a cPanel API 1 response, normalized as a
     * list of [ { level:"info|warn|error", content:"..." }, ... ]
     *
     * @method find_cpanel1_messages
     * @param {object} resp The parsed API JSON response
     * @return {array} The messages that the API call returned
     */
    var find_cpanel1_messages = function(resp) {
        if (!resp) {
            return [{
                level: "error",
                content: _unknown_error_msg()
            }];
        }

        if ("error" in resp) {
            var err = resp.error;
            return [{
                level: "error",
                content: err || _unknown_error_msg()
            }];
        }

        return [];
    };

    /**
     * Return a list of messages from a cPanel API 2 response, normalized as a
     * list of [ { level:"info|warn|error", content:"..." }, ... ]
     *
     * @method find_cpanel2_messages
     * @param {object} resp The parsed API JSON response
     * @return {array} The messages that the API call returned
     */
    var find_cpanel2_messages = function(resp) {
        if (!resp || !resp.cpanelresult) {
            return [{
                level: "error",
                content: _unknown_error_msg()
            }];
        }

        if ("error" in resp.cpanelresult) {
            var err = resp.cpanelresult.error;
            return [{
                level: "error",
                content: err || _unknown_error_msg()
            }];
        }

        return [];
    };

    /**
     * Return a list of messages from a UAPI response, normalized as a
     * list of [ { level:"info|warn|error", content:"..." }, ... ]
     *
     * @method find_uapi_messages
     * @param {object} resp The parsed API JSON response
     * @return {array} The messages that the API call returned
     */
    var find_uapi_messages = function(resp) {
        var messages = [];

        if (!resp || typeof resp !== "object") {
            messages.push({
                level: "error",
                content: _unknown_error_msg()
            });
        } else {
            if (resp.errors) {
                resp.errors.forEach(function(m) {
                    messages.push({
                        level: "error",
                        content: String(m)
                    });
                });
            }

            if (resp.messages) {
                resp.messages.forEach(function(m) {
                    messages.push({
                        level: "info",
                        content: String(m)
                    });
                });
            }
        }

        return messages;
    };

    var _parse_response = function(status_finder, message_finder, data_getter, resp) {
        var data = null,
            resp_status = false,
            err = null,
            messages = null;

        if (typeof resp === "string") {
            try {
                resp = YAHOO.lang.JSON.parse(resp);
            } catch (e) {
                try {
                    window.console.warn(resp, e);
                } catch (ee) {}
                err = LOCALE.maketext("The API response could not be parsed.");
                resp = null;
            }
        }

        if (!err) {
            try {
                data = data_getter(resp);
                if (data === undefined) {
                    data = null;
                }
            } catch (e) {  //

                // message_finder will find out what needs to be reported.
            }

            messages = message_finder(resp);

            resp_status = status_finder(resp);

            // We can't depend on the first message being an error.
            var errors = messages.filter(function(m) {
                return m.level === "error";
            });
            if (errors && errors.length) {
                err = errors[0].content;
            }
        }

        return {
            cpanel_status: resp_status,
            cpanel_raw: resp,
            cpanel_data: data,
            cpanel_error: err,
            cpanel_messages: messages
        };
    };

    /**
     * Parse a YUI asyncRequest response object to extract
     * the interesting parts of a UAPI call response.
     *
     * @method parse_uapi_response
     * @param {object} resp The asyncRequest response object
     * @return {object} See _parse_response for the format of this object.
     */
    var parse_uapi_response = function(resp) {
        return _parse_response(find_uapi_status, find_uapi_messages, _get_uapi_data, resp);
    };

    /**
     * Parse a YUI asyncRequest response object to extract
     * the interesting parts of a cPanel API 1 call response.
     *
     * @method parse_cpanel1_response
     * @param {object} resp The asyncRequest response object
     * @return {object} See _parse_response for the format of this object.
     */
    var parse_cpanel1_response = function(resp) {
        return _parse_response(find_cpanel1_status, find_cpanel1_messages, _get_cpanel1_data, resp);
    };

    /**
     * Parse a YUI asyncRequest response object to extract
     * the interesting parts of a cPanel API 2 call response.
     *
     * @method parse_cpanel2_response
     * @param {object} resp The asyncRequest response object
     * @return {object} See _parse_response for the format of this object.
     */
    var parse_cpanel2_response = function(resp) {
        return _parse_response(find_cpanel2_status, find_cpanel2_messages, _get_cpanel2_data, resp);
    };

    /**
     * Parse a YUI asyncRequest response object to extract
     * the interesting parts of a WHM API v1 call response.
     *
     * @method parse_whm1_response
     * @param {object} resp The asyncRequest response object
     * @return {object} See _parse_response for the format of this object.
     */
    var parse_whm1_response = function(resp) {
        return _parse_response(find_whm1_status, find_whm1_messages, _get_whm1_data, resp);
    };

    var _cpanel_parsers = {
        1: parse_cpanel1_response,
        2: parse_cpanel2_response,
        3: parse_uapi_response
    };
    var _whm_parsers = {
        1: parse_whm1_response

        // 3: parse_uapi_response    -- NO SERVER-SIDE IMPLEMENTATION YET
    };

    YAHOO.lang.augmentObject(api, {

        // We expose these because datasource.js depends on them.
        find_cpanel2_status: find_cpanel2_status,
        find_cpanel2_messages: find_cpanel2_messages,
        find_whm1_status: find_whm1_status,
        find_whm1_messages: find_whm1_messages,
        find_uapi_status: find_uapi_status,
        find_uapi_messages: find_uapi_messages,

        // Exposed for testing
        reduce_whm1_list_data: reduce_whm1_list_data,
        parse_whm1_response: parse_whm1_response,
        parse_cpanel1_response: parse_cpanel1_response,
        parse_cpanel2_response: parse_cpanel2_response,
        parse_uapi_response: parse_uapi_response,

        construct_query: construct_api_query,
        construct_url_path: construct_url_path,
        get_transaction_args: get_transaction_args,

        find_api_version: find_api_version
    });
    CPANEL.api = api;

}(window));
