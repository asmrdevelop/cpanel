/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* ----------------------------------------------------------------------------------
 * Tasks:
 *  1) Why is the Y method defined here, shouldn't it be in the yahoo.js.
 *  2) Add YUIDocs to all the methods and published variables.
 *  3) Why is the custom event stuff defined here, should also be in yahoo.js
 *  probably.
 *  4) failureEvent handler includes non-localized strings.
 *----------------------------------------------------------------------------------*/

// --------------------------------------------------------------------------------------
// Define the CPANEL global object
// --------------------------------------------------------------------------------------
(function() {
    var _y;

    // --------------------------------------------------------------------------------------
    // Create a Y function/object that allows rudimentary use of the
    // Y.one() and Y.all() syntaxes from YUI 3. This should eventually make for
    // easier porting to YUI 3.
    // --------------------------------------------------------------------------------------
    if (YAHOO && YAHOO.util && YAHOO.util.Selector && (!("Y" in window) || (window.Y === YAHOO))) {
        _y = (function() {
            var query = YAHOO.util.Selector.query;
            var DOM = YAHOO.util.Dom;

            /**
             * Select the first node that matches the passed selector.
             * This is similar to the tools provided by YUI3, but does
             * not do any further processing the node before its returned.
             * @param  {String} sel CSS selector for the node.
             * @return {HTMLElement|null}     The first matching node if it exists, or null.
             */
            var one = function(sel) {
                var root = (this === _y) ? null : this;
                return query(sel, root, true);
            };

            /**
             * Select all the nodes that match the passed selector
             * This is similar to the tools provided by YUI3, but does
             * not do any further processing the node before its returned.
             * @param  {String} sel CSS selector for the nodes.
             * @return {Array of HTMLElements} All elements that match the given selector.
             */
            var all = function(sel) {
                var root = (this === _y) ? null : this;
                return query(sel, root);
            };

            /**
             * The CPANEL.Y function
             * This mimics the syntax of YUI 3 Node's .one() and .all().
             *
             * Valid syntaxes:
             * Y.one(selector)
             * Y.all(selector)
             * Y(domnode_or_id).one(selector)
             * Y(domnode_or_id).all(selector)
             *
             * NOTE: Unlike getElementsByTagName et al., all() returns an Array, not an HTML collection.
             *
             * @param  {HTMLElement|String} domnode Node in the document to start from.
             * If its a string, it can be either a "#id" or just the "id".
             * @return {Object}         Object that provides one() and all() methods for
             * ad dom node similar to YUI3 model. Remember, this is only a partial implementation
             * of this model focused only on the query semantics, not the deeper node wrapper
             * implemenation.
             */
            var _y = function(domnode) {
                if (typeof domnode === "string") {
                    domnode = domnode.replace(/^#/, "");
                }
                domnode = DOM.get(domnode);
                return {
                    one: one.bind(domnode),
                    all: all.bind(domnode)
                };
            };
            _y.one = one;
            _y.all = all;

            return _y;
        })();
    }

    var url_path = location.pathname;
    var path_match = (url_path.match(/((?:\/cpsess\d+)?)(?:\/([^\/]+))?/) || []);

    // To determine the application we're running, first check the port, then the URL.
    //
    // This will work in any context except a proxy URL to cpanel or webmail
    // that accesses a URL outside /frontend (cpanel) or /webmail (webmail),
    // but URLs like that are non-production by defintion.
    var port_path_app = {
        2082: "cpanel",
        2083: "cpanel",
        2086: "whostmgr",
        2087: "whostmgr",
        2095: "webmail",
        2096: "webmail",
        frontend: "cpanel",
        webmail: "webmail"
    };

    var security_token = path_match[1] || "";

    var cpanel = {

        Y: _y,

        /**
         * !!! Do not use this in new code !!! Builds a url from the current location and security token
         * @legacy
         * @static
         * @class CPANEL
         * @type String
         * @name base_path
         */
        base_path: function() {
            return location.protocol + "//" + location.hostname + ":" + location.port + (security_token || "") + "/";
        },

        /**
         * Current security token for the page
         * @static
         * @class CPANEL
         * @type String
         * @name security_token
         */
        security_token: security_token,

        /**
         * Flag that identifies it the browser is running in a touch enabled environment.
         * @static
         * @class CPANEL
         * @type Boolean
         * @name is_touchscreen
         */
        is_touchscreen: "orientation" in window,

        /**
         * Unique name of the application
         * @static
         * @class CPANEL
         * @type String
         * @name application
         */
        application: port_path_app[location.port] || port_path_app[path_match[2]] || "whostmgr",

        /**
         * Return whether we are running inside cpanel or something else (e.g., WHM)
         * NOTE: Reference window.CPANEL rather than cpanel for testing.
         *
         * @static
         * @class CPANEL
         * @method is_cpanel
         * @type boolean
         */
        is_cpanel: function() {
            return (/cpanel/i).test(window.CPANEL.application);
        },

        /**
         * Return whether we are running inside WHM or something else (e.g., cpanel)
         * NOTE: Reference window.CPANEL rather than cpanel for testing.
         *
         * @static
         * @class CPANEL
         * @method is_whm
         * @type boolean
         */
        is_whm: function() {
            return (/wh/i).test(window.CPANEL.application);
        },

        /**
         * Flag to indicate if the document has a textContent attribute.
         * @static
         * @class CPANEL
         * @type Boolean
         * @name has_text_content
         */
        has_text_content: ("textContent" in document),

        /**
         * Provide the CPANEL object with the namespace capabilities from YUI2
         * @static
         * @class CPANEL
         * @name namespace
         * @param [VarParam String] one or more strings that represent namespaces to attach to the
         * CPANEL object. Namespaces in a string should be separated by a . just like they would be
         * defined in Javascript. The leading CPANEL name is optional and will be skipped since the
         * root CPANEL object already exists.
         * @source - YUI 2.9.0 Code Distribution
         */
        "namespace": function() {
            var a = arguments,
                o = null,
                i, j, d;
            for (i = 0; i < a.length; i = i + 1) {
                d = ("" + a[i]).split(".");
                o = window["CPANEL"];

                // CPANEL is implied, so it is ignored if it is included
                for (j = (d[0] === "CPANEL") ? 1 : 0; j < d.length; j = j + 1) {

                    // Only create if it doesn't already exist
                    o[d[j]] = o[d[j]] || {};
                    o = o[d[j]];
                }
            }
            return o;
        }
    };

    // Register the cpanel static class with YUI so it can participate in loading scheme
    YAHOO.register("cpanel", cpanel, {
        version: "1.0.0",
        build: "1"
    });

    // Exports
    window["CPANEL"] = cpanel;
})();


// --------------------------------------------------------------------------------------
// include global shortcuts to Yahoo Libraries
// --------------------------------------------------------------------------------------
if (window.YAHOO && YAHOO.util) {

    // Exports
    window.DOM = YAHOO.util.Dom;
    window.EVENT = YAHOO.util.Event;
}


// --------------------------------------------------------------------------------------
// Install our custom events and event handling routines
// --------------------------------------------------------------------------------------
if (window.YAHOO && YAHOO.util) {

    // Define our custom events for the framework.
    if (YAHOO.util.CustomEvent) {
        CPANEL.align_panels_event = new YAHOO.util.CustomEvent("align panels event");
        CPANEL.align_panels = CPANEL.align_panels_event.fire.bind(CPANEL.align_panels_event);
    }

    // Define is we want to throw errors when we process events.
    if (YAHOO.util.Event) {
        YAHOO.util.Event.throwErrors = true;
    }

    // Setup the default failure event hander for AJAX and related connection based calls.
    if (YAHOO.util.Connect) {
        YAHOO.util.Connect.failureEvent.subscribe(function(eventType, args) {
            if ("no_ajax_authentication_notices" in CPANEL) {
                return;
            }

            for (var i = 0, l = args.length; i < l; i++) {
                if (args[i] && args[i].status) {
                    switch (args[i].status) {
                        case 401: // unauthorized
                        case 403: // forbidden
                        case 407: // Proxy Authentication Required
                        case 505: // HTTP version not supported.
                            if (window.confirm("Your login session has expired.\nClick \"OK\" to log in again.\nClick \"Cancel\" to stay on the page.")) {
                                window.top.location.reload();
                            }
                            break;
                    }
                }
            }
        });
    }
}
