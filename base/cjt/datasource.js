(function(window) {

    "use strict";

    var CPANEL = window.CPANEL;
    var YAHOO = window.YAHOO;

    YAHOO.util.DataSourceBase.prototype.get_field_parser = function(field) {
        var fields, parser = "string";
        try {
            fields = this.responseSchema.fields;
        } catch (e) {}
        if (fields) {
            for (var f = 0; f < fields.length; f++) {
                if (fields[f].key === field) {
                    parser = fields[f].parser || parser;
                    break;
                }
            }
        }

        return parser;
    };


    var _std_CXD_opts = {
        responseType: YAHOO.util.DataSource.TYPE_JSON,
        connXhrMode: "cancelStaleRequests",
        connMethodPost: true
    };

    var CXD_OPTS = {};
    if (CPANEL.is_whm()) {
        CXD_OPTS[1] = YAHOO.lang.augmentObject({}, _std_CXD_opts);
        CXD_OPTS[1].responseSchema = {
            resultsList: "data",
            metaFields: {
                total_records: "metadata.chunk.records",
                before_filter: "metadata.filter.filtered",
                metadata: "metadata"
            }
        };
    } else {
        CXD_OPTS[2] = YAHOO.lang.augmentObject({}, _std_CXD_opts);
        CXD_OPTS[3] = YAHOO.lang.augmentObject({}, _std_CXD_opts);

        CXD_OPTS[2].responseSchema = {
            resultsList: "cpanelresult.data",
            metaFields: {
                total_records: "cpanelresult.paginate.total_results",
                before_filter: "cpanelresult.before_filter",
                metadata: "cpanelresult.metadata"
            }
        };

        CXD_OPTS[3].responseSchema = {
            resultsList: "data",
            metaFields: {
                total_records: "metadata.paginate.total_results",
                before_filter: "metadata.records_before_filter",
                metadata: "metadata"
            }
        };
    }


    // class CPANEL_XHR_DataSource
    //
    // Subclass wrapper around YUI XHRDataSource for cPanel and WHM APIs
    // Additional opts:
    //  fields:       for the responseSchema
    //  func:         the function name
    //  module:       the module name (n/a in WHM)
    //  api_version:  API version passed to CPANEL.api.construct_query
    //  request_data: default data object to be added to request objects

    var CPANEL_XHRDataSource = function(opts) {
        var my_opts = {};

        if (opts) {
            YAHOO.lang.augmentObject(my_opts, opts);
        }

        if (typeof my_opts.api_version === "undefined") {
            my_opts.api_version = CPANEL.api.find_api_version(); // default API version
        } else {
            my_opts.api_version = +my_opts.api_version;
        }

        var api_opts = CXD_OPTS[my_opts.api_version];
        if (!api_opts) {
            throw "Invalid API version: " + my_opts.api_version;
        }

        // Don't override things that are passed in.
        YAHOO.lang.augmentObject(my_opts, api_opts);

        if (my_opts.fields) {
            my_opts.responseSchema.fields = my_opts.fields;
            delete my_opts.fields;
        }

        // A dummy URL since makeConnection will feed in the real URL.
        CPANEL_XHRDataSource.superclass.constructor.call(this, "/", my_opts);
    };
    YAHOO.lang.extend(CPANEL_XHRDataSource, YAHOO.util.XHRDataSource, {

        // Extract tabular data from WHM v1, and check for API-level errors.
        parseJSONData: function(req, parsed) {
            var use_whm1 = (CPANEL.is_whm() && (this.api_version === 1));
            if (use_whm1) {
                var metadata = parsed.metadata;
                var to_reduce = !metadata || !metadata.payload_is_literal || (metadata.payload_is_literal === "0");

                if (to_reduce) {
                    parsed.data = CPANEL.api.reduce_whm1_list_data(parsed.data);
                }
            }

            var ret = CPANEL_XHRDataSource.superclass.parseJSONData.call(this, req, parsed);

            var messages;
            if (use_whm1) {
                if (!CPANEL.api.find_whm1_status(parsed)) {
                    messages = CPANEL.api.find_whm1_messages(parsed);
                }
            } else {
                if (this.api_version === 3) {
                    if (!CPANEL.api.find_uapi_status(parsed)) {
                        messages = CPANEL.api.find_uapi_messages(parsed);
                    }
                } else if (!CPANEL.api.find_cpanel2_status(parsed)) {
                    messages = CPANEL.api.find_cpanel2_messages(parsed);
                }
            }

            if (messages) {
                ret.error = true;
                var errs = messages.filter(function(m) {
                    return m.level === "error";
                });
                if (errs.length) {
                    ret.cpanel_error = errs[0].content;
                }
            }

            return ret;
        },

        // This expects a CPANEL.api request object but will add in func/module/version
        // We fall back to default XHRDataSource if the request is not an object.
        makeConnection: function(req, cb, clr) {
            if (typeof req === "object") {

                // copy, then add module/func as needed
                req = YAHOO.lang.JSON.parse(YAHOO.lang.JSON.stringify(req));

                var that = this;
                ["module", "func"].forEach(function(key) {
                    if (!(key in req) && (key in that)) {
                        req[key] = that[key];
                    }
                });

                if (!req.api_data) {
                    req.api_data = {};
                }
                req.api_data.version = this.api_version;

                if (this.request_data) {
                    if (!req.data) {
                        req.data = {};
                    }
                    YAHOO.lang.augmentObject(req.data, this.request_data);
                }

                this.liveData = CPANEL.api.construct_url_path(req);

                req = CPANEL.api.construct_query(req);
            }

            return CPANEL_XHRDataSource.superclass.makeConnection.call(this, req, cb, clr);
        }
    });


    var export_obj = {
        CPANEL_XHRDataSource: CPANEL_XHRDataSource
    };
    CPANEL.datasource = export_obj;

    return export_obj;
}(window));
