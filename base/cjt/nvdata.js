/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

CPANEL.nvdata = {

    page_key: location.pathname.replace(new RegExp("^" + CPANEL.security_token), "").replace(/\//g, "_"),

    // NOTE: This does NOT check to be sure we don't clobber something
    // already registered!
    // This works similarly to how a YUI custom event works: args is either
    // passed to the getter function, or is the context if
    // override is true.
    // Additionally, setting an empty getter deletes the key.
    register: function(key, getter, args, override) {
        if (!getter) {
            delete CPANEL.nvdata._getters[key];
        } else if (!args) { // register, simple case
            CPANEL.nvdata._getters[key] = getter;
        } else if (!override) { // args is an argument
            CPANEL.nvdata._getters[key] = getter.bind(window, args);
        } else { // args is the context if override is true
            CPANEL.nvdata._getters[key] = getter.bind(args);
        }
    },

    _getters: {},

    get_page_nvdata: function() {
        var page_nvdata = {};
        for (var key in CPANEL.nvdata._getters) {
            page_nvdata[key] = CPANEL.nvdata._getters[key]();
        }

        return page_nvdata;
    },

    // With no arguments: saves page nvdata.
    // With one object argument:
    //  if arg is an object: object is saved as page nvdata.
    //  if arg is a string: string used instead of page_key
    // With two arguments: key/value are saved independently of page nvdata.
    // Returns the CPANEL.api return value.
    save: function(key, value) {
        if (!CPANEL.api) {
            throw "Load api.js.";
        }

        if (!key) {
            key = key || CPANEL.nvdata.page_key;
            value = YAHOO.lang.JSON.stringify(CPANEL.nvdata.get_page_nvdata());
        } else if (typeof key === "object") {
            value = YAHOO.lang.JSON.stringify(key);
            key = CPANEL.nvdata.page_key;
        } else if (!value) {
            value = YAHOO.lang.JSON.stringify(CPANEL.nvdata.get_page_nvdata());
        }

        if (/^wh/i.test(CPANEL.application)) {
            return CPANEL.api({
                func: "nvset",
                data: {
                    key1: key,
                    value1: value
                }
            });
        } else {
            var data = {
                names: key
            };
            data[key] = value;
            return CPANEL.api({
                module: "NVData",
                func: "set",
                data: data
            });
        }
    },

    // set nvdata silently
    // LEGACY - do not use in new code
    set: function(key, value) {
        var api2_call = {
            cpanel_jsonapi_version: 2,
            cpanel_jsonapi_module: "NVData",
            cpanel_jsonapi_func: "set",
            names: key
        };
        api2_call[key] = value;

        var callback = {
            success: function(o) {},
            failure: function(o) {}
        };

        YAHOO.util.Connect.asyncRequest("GET", CPANEL.urls.json_api(api2_call), callback, "");
    }
}; // end nvdata object
