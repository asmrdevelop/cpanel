
//--- start /usr/local/cpanel/base/cjt/compatibility.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/indexOf
if (!("indexOf" in Array.prototype)) {
    Array.prototype.indexOf = function(elt /* , from*/ ) {
        var len = this.length >>> 0;

        var from = Number(arguments[1]) || 0;
        from = (from < 0) ? Math.ceil(from) : Math.floor(from);
        if (from < 0) {
            from += len;
        }

        for (; from < len; from++) {
            if (from in this &&
                this[from] === elt) {
                return from;
            }
        }
        return -1;
    };
}


// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/lastIndexOf
if (!("lastIndexOf" in Array.prototype)) {
    Array.prototype.lastIndexOf = function(elt /* , from*/ ) {
        var len = this.length;

        var from = Number(arguments[1]);
        if (isNaN(from)) {
            from = len - 1;
        } else {
            from = (from < 0) ? Math.ceil(from) : Math.floor(from);
            if (from < 0) {
                from += len;
            } else if (from >= len) {
                from = len - 1;
            }
        }

        for (; from > -1; from--) {
            if (from in this &&
                this[from] === elt) {
                return from;
            }
        }
        return -1;
    };
}


// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/filter
if (!("filter" in Array.prototype)) {
    Array.prototype.filter = function(fun /* , thisp*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        var res = [];
        var thisp = arguments[1];
        for (var i = 0; i < len; i++) {
            if (i in this) {
                var val = this[i]; // in case fun mutates this
                if (fun.call(thisp, val, i, this)) {
                    res.push(val);
                }
            }
        }

        return res;
    };
}


// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/forEach
if (!("forEach" in Array.prototype)) {
    Array.prototype.forEach = function(fun /* , thisp*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        var thisp = arguments[1];
        for (var i = 0; i < len; i++) {
            if (i in this) {
                fun.call(thisp, this[i], i, this);
            }
        }
    };
}


// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/every
if (!("every" in Array.prototype)) {
    Array.prototype.every = function(fun /* , thisp*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        var thisp = arguments[1];
        for (var i = 0; i < len; i++) {
            if (i in this && !fun.call(thisp, this[i], i, this)) {
                return false;
            }
        }

        return true;
    };
}


// https://developer.mozilla.org/En/Core_JavaScript_1.5_Reference/Objects/Array/Map
if (!("map" in Array.prototype)) {
    Array.prototype.map = function(fun /* , thisp*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        var res = new Array(len);
        var thisp = arguments[1];
        for (var i = 0; i < len; i++) {
            if (i in this) {
                res[i] = fun.call(thisp, this[i], i, this);
            }
        }

        return res;
    };
}


// https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/Array/some
if (!("some" in Array.prototype)) {
    Array.prototype.some = function(fun /* , thisp*/ ) {
        var i = 0,
            len = this.length >>> 0;

        if (typeof fun != "function") {
            throw new TypeError();
        }

        var thisp = arguments[1];
        for (; i < len; i++) {
            if (i in this &&
                fun.call(thisp, this[i], i, this)) {
                return true;
            }
        }

        return false;
    };
}


// https://developer.mozilla.org/En/Core_JavaScript_1.5_Reference/Global_Objects/Array/Reduce
if (!("reduce" in Array.prototype)) {
    Array.prototype.reduce = function(fun /* , initial*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        // no value to return if no initial value and an empty array
        if (len == 0 && arguments.length == 1) {
            throw new TypeError();
        }

        var i = 0;
        if (arguments.length >= 2) {
            var rv = arguments[1];
        } else {
            do {
                if (i in this) {
                    var rv = this[i++];
                    break;
                }

                // if array contains no values, no initial value to return
                if (++i >= len) {
                    throw new TypeError();
                }
            }
            while (true);
        }

        for (; i < len; i++) {
            if (i in this) {
                rv = fun.call(null, rv, this[i], i, this);
            }
        }

        return rv;
    };
}


// https://developer.mozilla.org/En/Core_JavaScript_1.5_Reference/Global_Objects/Array/ReduceRight
if (!("reduceRight" in Array.prototype)) {
    Array.prototype.reduceRight = function(fun /* , initial*/ ) {
        var len = this.length >>> 0;
        if (typeof fun != "function") {
            throw new TypeError();
        }

        // no value to return if no initial value, empty array
        if (len == 0 && arguments.length == 1) {
            throw new TypeError();
        }

        var i = len - 1;
        if (arguments.length >= 2) {
            var rv = arguments[1];
        } else {
            do {
                if (i in this) {
                    var rv = this[i--];
                    break;
                }

                // if array contains no values, no initial value to return
                if (--i < 0) {
                    throw new TypeError();
                }
            }
            while (true);
        }

        for (; i >= 0; i--) {
            if (i in this) {
                rv = fun.call(null, rv, this[i], i, this);
            }
        }

        return rv;
    };
}


// add "trim" functionality to the String prototype
if (!("trim" in String.prototype)) {
    String.prototype.trim = function() {
        return this.replace(/^\s+|\s+$/g, "");
    };
}


// https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Function/bind
if (!Function.prototype.bind) {
    Function.prototype.bind = function(oThis) {
        if (typeof this !== "function") {

            // closest thing possible to the ECMAScript 5 internal IsCallable function
            throw new TypeError("Function.prototype.bind - what is trying to be bound is not callable");
        }

        var fSlice = Array.prototype.slice,
            aArgs = fSlice.call(arguments, 1),
            fToBind = this,
            fNOP = function() {},
            fBound = function() {
                return fToBind.apply(
                    (this instanceof fNOP) ? this : (oThis || window),
                    aArgs.concat(fSlice.call(arguments))
                );
            };

        fNOP.prototype = this.prototype;
        fBound.prototype = new fNOP();

        return fBound;
    };
}


// https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Object/keys
// Tweaked a bit.
if (!Object.keys) {
    Object.keys = function(o) {
        if (o !== Object(o)) {
            throw new TypeError("Object.keys called on non-object.");
        }

        var ret = [],
            p, HOP = Object.prototype.hasOwnProperty;

        for (p in o) {
            if (HOP.call(o, p)) {
                ret.push(p);
            }
        }

        return ret;
    };
}


if (!Date.now) {
    Date.now = function now() {
        return +(new Date());
    };
}


// ----------------------------------------------------------------------
// Compatibility shim for btoa, atob
//
// NOTE: Remove this once support for IE <= 9 is dropped.
// https://bitbucket.org/davidchambers/base64.js
// d29f8a098a55
if (!window.atob) {
    (function() {
        var
            object = typeof window != "undefined" ? window : exports,
            chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",

            // For some reason, this breaks in Opera.
            INVALID_CHARACTER_ERR = (function() {

                // fabricate a suitable error object
                try {
                    document.createElement("$");
                } catch (error) {
                    return error;
                }
            }());

        // encoder -- REMOVED FOR CPANEL

        // decoder
        // [https://gist.github.com/1020396] by [https://github.com/atk]
        object.atob || (
            object.atob = function(input) {
                input = input.replace(/=+$/, "");
                if (input.length % 4 == 1) {
                    throw INVALID_CHARACTER_ERR;
                }
                for (

                    // initialize result and counters
                    var bc = 0, bs, buffer, idx = 0, output = "";

                    // get next character
                    buffer = input.charAt(idx++);

                    // character found in table? initialize bit storage and add its ascii value;
                    ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,

                        // and if not first of each 4 characters,
                        // convert the first 8 bits to one ascii character
                        bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0
                ) {

                    // try to find character in table (0-63, not found => -1)
                    buffer = chars.indexOf(buffer);
                }
                return output;
            });
    }());
}

//--- end /usr/local/cpanel/base/cjt/compatibility.js ---

//--- start /usr/local/cpanel/base/cjt/prototypes.js ---
// THIS FILE CONTAINS ONLY CUSTOM ADDITIONS TO BUILT-IN JAVSCRIPT PROTOTYPES.
// COMPATIBILITY FUNCTIONS TO PROTOTYPES GO IN compatibility.js.

(function() {

    /**
     * This module contains extesions to the standard Javascript String object.
     * @module  String Extensions
     */

    /**
     * Left pads the string with leading characters. Will use spaces if
     * the padder parameter is not defined. Will pad with "0" if the padder
     * is 0.
     * @method  lpad
     * @param  {Number} len    Length of the padding
     * @param  {String} padder Characters to pad with.
     * @return {String}        String padded to the full width defined by len parameter.
     */
    String.prototype.lpad = function(len, padder) {
        if (padder === 0) {
            padder = "0";
        } else if (!padder) {
            padder = " ";
        }

        var deficit = len - this.length;
        var pad = "";
        var padder_length = padder.length;
        while (deficit > 0) {
            pad += padder;
            deficit -= padder_length;
        }
        return pad + this;
    };

    /**
     * Reverse the characters in a string.
     * @return {String} New string with characters reversed.
     */
    String.prototype.reverse = function() {
        return this.split("").reverse().join("");
    };

    // add html_encode functionality to the String object
    // Copying the logic found in YUI 2.9.0 YAHOO.lang.escapeHTML()
    var html_chars = {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#x27;",
        "/": "&#x2F;",
        "`": "&#x60;"
    };

    var html_chars_regex = /[&<>"'\/`]/g;
    var html_function = function(match) {
        return html_chars[match];
    };

    /**
     * Encode the string using html encoding rules
     * @method  html_encode
     * @return {String} Encoded html string.
     */
    String.prototype.html_encode = function() {
        return this.replace(html_chars_regex, html_function);
    };

    // Perl has \Q\E for this, but JS offers no such nicety.
    var escapees_regexp = /([\\^$*+?.()|{}\[\]])/g;

    /**
     * Encode the regular expression.
     * @method  regexp_encode
     * @return {String} Encoded regular expression
     */
    String.prototype.regexp_encode = function() {
        return this.replace(escapees_regexp, "\\$1");
    };
})();

(function() {

    /**
     * This module contains extesions to the standard Javascript Array object.
     * @module  Array Extensions
     */


    // COMPARABLE TO SQL SORTS: EACH ARGUMENT SPECIFIES A "TRANSFORM" FUNCTION
    // THAT GENERATES A COMPARISON VALUE FOR EACH MEMBER OF THE ARRAY.
    //
    // OR, YOU CAN WRITE A PROPERTY OR METHOD NAME AS A STRING.
    // INDICATE REVERSAL WITH A '!' AS THE FIRST CHARACTER.
    //
    // EXAMPLE: SORT DATES BY MONTH, BACKWARDS BY YEAR, AND SOMETHING ELSE
    // BY DOING THIS:
    // datesArray.sort_by('getMonth','!getYear',function (d) { ... })
    //
    // FOR GENERIC REVERSAL OF A TRANSFORM FUNCTION,
    // DEFINE A reverse PROPERTY ON IT AS true.
    Array.prototype.sort_by = function() {
        var this_length = this.length;

        if (this_length === 0) {
            return this;
        }

        var xformers = [];
        var xformers_length = arguments.length;
        for (var s = 0; s < xformers_length; s++) {
            var cur_xformer = arguments[s];

            var xformer_func;
            var reverse = false;

            if (cur_xformer instanceof Function) {
                xformer_func = cur_xformer;
                reverse = cur_xformer.reverse || false;
            } else {
                reverse = ((typeof cur_xformer === "string" || cur_xformer instanceof String) && cur_xformer.charAt(0) === "!");
                if (reverse) {
                    cur_xformer = cur_xformer.substring(1);
                }

                var referenced = this[0][cur_xformer];
                var isFunc = (referenced instanceof Function);
                xformer_func = isFunc ?
                    function(i) {
                        return i[cur_xformer]();
                    } :
                    function(i) {
                        return i[cur_xformer];
                    };
            }

            xformer_func.reverse_val = reverse ? -1 : 1;

            xformers.push(xformer_func);
        }

        var xformed_values = [];
        for (var i = 0; i < this_length; i++) {
            cur_value = this[i];
            var cur_xformed_values = [];
            for (var x = 0; x < xformers_length; x++) {
                cur_xformed_values.push(xformers[x](cur_value));
            }
            cur_xformed_values.push(i); // Do this for cross-browser stable sorting.
            cur_xformed_values.item = cur_value;
            xformed_values.push(cur_xformed_values);
        }

        var index, _xformers_length, first_xformed, second_xformed;
        var sorter = function(first, second) {
            index = 0;
            _xformers_length = xformers_length; // save on scope lookups
            while (index < _xformers_length) {
                first_xformed = first[index];
                second_xformed = second[index];
                if (first_xformed > second_xformed) {
                    return (1 * xformers[index].reverse_val);
                } else if (first_xformed < second_xformed) {
                    return (-1 * xformers[index].reverse_val);
                }
                index++;
            }
            return 0;
        };

        xformed_values.sort(sorter);

        for (var xv = 0; xv < this_length; xv++) {
            this[xv] = xformed_values[xv].item;
        }

        return this;
    };

    /**
     * Finds all the unique items in the Array returning them as a new Array.
     * @method  unique
     * @return {Array} Unique items in the array as determined by ===
     * @source http://www.martienus.com/code/javascript-remove-duplicates-from-array.html
     */
    Array.prototype.unique = function() {
        var r = [];

        bigloop: for (var i = 0, n = this.length; i < n; i++) {
            for (var x = 0, y = r.length; x < y; x++) {
                if (r[x] === this[i]) {
                    continue bigloop;
                }
            }
            r[y] = this[i];
        }

        return r;
    };

    /**
     * Extends the Array object to be able to retrieve
     * the smallest element in the array by value.
     * @method  max
     * @return {Object} the smallest element in the array
     * by value using < comparison.
     */
    Array.prototype.min = function() {
        var min = this[this.length - 1];
        for (var i = this.length - 2; i >= 0; i--) {
            if (this[i] < min) {
                min = this[i];
            }
        }

        return min;
    };

    /**
     * Extends the Array object to be able to retrieve
     * the largest element in the array by value.
     * @method  max
     * @return {Object} the largest element in the array
     * by value using > comparison.
     */
    Array.prototype.max = function() {
        var max = this[this.length - 1];
        for (var i = this.length - 2; i >= 0; i--) {
            if (this[i] > max) {
                max = this[i];
            }
        }

        return max;
    };

})();

//--- end /usr/local/cpanel/base/cjt/prototypes.js ---

//--- start /usr/local/cpanel/base/cjt/cpanel.js ---
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

//--- end /usr/local/cpanel/base/cjt/cpanel.js ---

//--- start /usr/local/cpanel/base/cjt/locale.js ---
/* eslint camelcase: 0 */
/* eslint guard-for-in: 0 */

(function(window) {
    "use strict";

    if (!window.CPANEL) {
        window.CPANEL = {};
    }

    var CPANEL = window.CPANEL;

    var DEFAULT_ELLIPSIS = {
        initial: "…{0}",
        medial: "{0}…{1}",
        "final": "{0}…",
    };

    var html_apos = "'".html_encode();
    var html_quot = "\"".html_encode();
    var html_amp  = "&".html_encode();
    var html_lt   = "<".html_encode();
    var html_gt   = ">".html_encode();

    // JS getUTCDay() starts from Sunday, but CLDR starts from Monday.
    var get_cldr_day = function(the_date) {
        var num = the_date.getUTCDay() - 1;
        return (num < 0) ? 6 : num;
    };

    var Locale = function() {};
    CPANEL.Locale = Locale;
    Locale._locales = {};
    Locale.add_locale = function(tag, construc) {
        Locale._locales[tag] = construc;
        construc.prototype._locale_tag = tag;
    };
    Locale.remove_locale = function(tag) { // For testing
        return delete Locale._locales[tag];
    };
    Locale.get_handle = function() {
        var cur_arg;
        var arg_count = arguments.length;
        for (var a = 0; a < arg_count; a++) {
            cur_arg = arguments[a];
            if (cur_arg in Locale._locales) {
                return new Locale._locales[cur_arg]();
            }
        }

        // We didn't find anything from the given arguments, so check _locales.
        // We can't trust JS's iteration order, so grab keys and take the first one.
        var loc = Object.keys(Locale._locales).min();

        return loc ? new Locale._locales[loc]() : new Locale();
    };

    // ymd_string_to_date will be smarter once case 52389 is done.
    // For now, we need the ymd order from the server.
    CPANEL.Locale.ymd = null;
    CPANEL.Locale.ymd_string_to_date = function(str) {
        var str_split = str.split(/\D+/);
        var ymd = this.ymd || "mdy"; // U.S. English;

        var day = str_split[ymd.indexOf("d")];
        var month = str_split[ymd.indexOf("m")];
        var year = str_split[ymd.indexOf("y")];

        // It seems unlikely that we'd care about ancient times.
        if (year && (year.length < 4)) {
            var deficit = 4 - year.length;
            year = String((new Date()).getFullYear()).substr(0, deficit) + year;
        }

        var date = new Date(year, month - 1, day);
        return isNaN(date.getTime()) ? undefined : date;
    };

    // temporary, until case 52389 is in
    CPANEL.Locale.date_template = null;
    Date.prototype.to_ymd_string = function() {
        var date = this;

        var template = CPANEL.Locale.date_template || "{month}/{day}/{year}"; // U.S. English
        return template.replace(/\{(?:month|day|year)\}/g, function(subst) {
            switch (subst) {
                case "{day}":
                    return date.getDate();
                case "{month}":
                    return date.getMonth() + 1;
                case "{year}":
                    return date.getFullYear();
            }
        });
    };

    var bracket_re = /([^~\[\]]+|~.|\[|\]|~)/g;

    // cf. Locale::Maketext re DEL
    var faux_comma = "\x07";
    var faux_comma_re = new RegExp(faux_comma, "g");

    // For outside a bracket group
    var tilde_chars = {
        "[": 1,
        "]": 1,
        "~": 1,
    };

    var underscore_digit_re = /^_(\d+)$/;

    var func_substitutions = {
        "#": "numf",
        "*": "quant",
    };

    // NOTE: There is no widely accepted consensus of exactly how to measure data
    // and which units to use for it.
    // For example, some bodies define "B" to mean bytes, while others don't.
    // (NB: SI defines "B" to mean bels.) Some folks use k for kilo; others use K.
    // Some say kilo should be 1,024; others say it's 1,000 (and "kibi" would be
    // 1,024). What we do here is at least in longstanding use at cPanel.
    var data_abbreviations = ["KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];

    // NOTE: args *must* be a list, not an Array object (as is permissible with
    // most other functions in this module).
    var _maketext = function(str /* , args list */ ) { // ## no extract maketext
        if (!str) {
            return;
        }

        str = this.LEXICON && this.LEXICON[str] || str;

        if (str.indexOf("[") === -1) {
            return String(str);
        }

        var assembled = [];

        var pieces = str.match(bracket_re);
        var pieces_length = pieces.length;

        var in_group = false;
        var bracket_args = "";

        var p, cur_p, a;

        PIECE: for (p = 0; p < pieces_length; p++) {
            cur_p = pieces[p];
            if ((cur_p === "[")) {
                if (in_group) {
                    throw "Invalid maketext string: " + str; // ## no extract maketext
                }

                in_group = true;
            } else if (cur_p === "]") {

                if (!in_group || !bracket_args) {
                    throw "Invalid maketext string: " + str; // ## no extract maketext
                }

                in_group = false;

                var real_args = bracket_args.split(",");
                var len = real_args.length;
                var func;

                if (len === 1) {
                    var arg = real_args[0].match(underscore_digit_re);
                    if (!arg) {
                        throw "Invalid maketext string: " + str; // ## no extract maketext
                    }
                    var looked_up = arguments[arg[1]];
                    if (typeof looked_up === "undefined") {
                        throw "Invalid argument \"" + arg[1] + "\" passed to maketext string: " + str; // ## no extract maketext
                    } else {
                        bracket_args = "";
                        assembled.push(looked_up);
                        continue PIECE;
                    }
                } else {
                    func = real_args.shift();
                    len -= 1;
                    func = func_substitutions[func] || func;

                    if (typeof this[func] !== "function") {
                        throw "Invalid function \"" + func + "\" in maketext string: " + str; // ## no extract maketext
                    }
                }

                if (bracket_args.indexOf(faux_comma) !== -1) {
                    for (a = 0; a < len; a++) {
                        real_args[a] = real_args[a].replace(faux_comma_re, ",");
                    }
                }

                var cur_arg, alen;

                for (a = 0; a < len; a++) {
                    cur_arg = real_args[a];
                    if (cur_arg.charAt(0) === "_") {
                        if (cur_arg === "_*") {
                            real_args.splice(a, 1);
                            for (a = 1, alen = arguments.length; a < alen; a++) {
                                real_args.push(arguments[a]);
                            }
                        } else {
                            var arg_num = cur_arg.match(underscore_digit_re);
                            if (arg_num) {
                                if (arg_num[1] in arguments) {
                                    real_args[a] = arguments[arg_num[1]];
                                } else {
                                    throw "Invalid variable \"" + arg_num[1] + "\" in maketext string: " + str; // ## no extract maketext
                                }
                            } else {
                                throw "Invalid maketext string: " + str; // ## no extract maketext
                            }
                        }
                    }
                }

                bracket_args = "";
                assembled.push(this[func].apply(this, real_args));
            } else if (cur_p.charAt(0) === "~") {
                var real_char = cur_p.charAt(1) || "~";
                if (in_group) {
                    if (real_char === ",") {
                        bracket_args += faux_comma;
                    } else {
                        bracket_args += real_char;
                    }
                } else if (real_char in tilde_chars) {
                    assembled.push(real_char);
                } else {
                    assembled.push(cur_p);
                }
            } else if (in_group) {
                bracket_args += cur_p;
            } else {
                assembled.push(cur_p);
            }
        }

        if (in_group) {
            throw "Invalid maketext string: " + str; // ## no extract maketext
        }

        return assembled.join("");
    };

    // Do this without YUI so testing via node.js is easier.
    // Most of what is here ports functionality from CPAN Locale::Maketext::Utils.
    var prototype_stuff = {
        LEXICON: (typeof window === "undefined") ?
            global.LEXICON || (global.LEXICON = {}) :
            window.LEXICON || (window.LEXICON = {}),

        /**
         * Use this method to localize a static string. These strings are harvested normally.
         *
         * @method maketext                                                                                         // ## no extract maketext
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         */
        maketext: _maketext, // ## no extract maketext

        /**
         * Like maketext() but does not lookup the phrase in the lexicon and compiles the phrase exactly as given.  // ## no extract maketext
         *
         * @note  In the current implementation this works just like maketext, but will need to be modified once we // ## no extract maketext
         * start doing lexicon lookups.
         *
         * @method maketext                                                                                         // ## no extract maketext
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         */
        makethis: _maketext,                                                                                       // ## no extract maketext

        /**
         * Use this method instead of maketext if you are passing a variable that contains the maketext template.   // ## no extract maketext
         *
         * @method makevar
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         * @example
         *
         * var translatable = LOCALE.translatable;                                                                  // ## no extract maketext
         * var template = translatable("What is this [numf,_1] thing.");                                            // ## no extract maketext
         * ...
         * var localized = LOCALE.makevar(template)
         *
         * or
         *
         * var template = LOCALE.translatable("What is this [numf,_1] thing.");                                     // ## no extract maketext
         * ...
         * var localized = LOCALE.makevar(template)
         */
        makevar: _maketext, // this is a marker method that is ignored in phrase harvesting, but is functionally equivalent to maketext otherwise. // ## no extract maketext

        /**
         * Marks the phrase as translatable for the harvester.                                                      // ## no extract maketext
         *
         * @method translatable                                                                                     // ## no extract maketext
         * @param  {String} str Translatable string
         * @return {Strung}     Same string, this is just a marker function for the harvester
         */
        translatable: function(str) { // ## no extract maketext
            return str;
        },

        _locale_tag: null,

        get_language_tag: function() {
            return this._locale_tag;
        },

        // These methods are locale-independent and should not need overrides.
        join: function(sep, list) {
            sep = String(sep);

            if (typeof list === "object") {
                return list.join(sep);
            } else {
                var str = String(arguments[1]);
                for (var a = 2; a < arguments.length; a++) {
                    str += sep + arguments[a];
                }
                return str;
            }
        },

        // Perl has undef, but JavaScript has both null *and* undefined.
        // Let's treat null as undefined since JSON doesn't know what
        // undefined is, so serializers use null instead.
        "boolean": function(condition, when_true, when_false, when_null) {
            if (condition) {
                return "" + when_true;
            }

            if (((arguments.length > 3) && (condition === null || condition === undefined))) {
                return "" + when_null;
            }

            return "" + when_false;
        },

        comment: function() {
            return "";
        },

        // A "dispatch" function for the output_* methods below.
        output: function(sub_func, str) {
            var that = this;

            var sub_args = Array.prototype.concat.apply([], arguments).slice(1);

            // Implementation of the chr() and amp() embeddable methods
            if (sub_args && typeof sub_args[0] === "string") {
                sub_args[0] = sub_args[0].replace(/chr\((\d+|\S)\)/g, function(str, p1) {
                    return that.output_chr(p1);
                });
                sub_args[0] = sub_args[0].replace(/amp\(\)/g, function(str) {
                    return that.output_amp();
                });
            }

            if (typeof this["output_" + sub_func] === "function") {
                return this["output_" + sub_func].apply(this, sub_args);
            } else {
                if (window.console) {
                    window.console.warn("Locale output function \"" + sub_func + "\" is not implemented.");
                }
                return str;
            }
        },

        output_apos: function() {
            return html_apos;
        },
        output_quot: function() {
            return html_quot;
        },

        // TODO: Implement embeddable methods described at
        // https://metacpan.org/pod/Locale::Maketext::Utils#asis()
        output_asis: String,
        asis: String,

        output_underline: function(str) {
            return "<u>" + str + "</u>";
        },
        output_strong: function(str) {
            return "<strong>" + str + "</strong>";
        },
        output_em: function(str) {
            return "<em>" + str + "</em>";
        },

        output_abbr: function(abbr, full) {
            return "<abbr title=\"__FULL__\">".replace(/__FULL__/, full) + abbr + "</abbr>";
        },

        output_acronym: function(abbr, full) {
            return this.output_abbr(abbr, full).replace(/^(<[a-z]+)/i, "$1 class=\"initialism\"");
        },

        output_class: function(str) {
            var cls = Array.prototype.slice.call(arguments, 1);

            return "<span class=\"" + cls.join(" ") + "\">" + str + "</span>";
        },
        output_chr: function(num) {
            return isNaN(+num) ? String(num) : String.fromCharCode(num).html_encode();
        },
        output_amp: function() {
            return html_amp;
        },
        output_lt: function() {
            return html_lt;
        },
        output_gt: function() {
            return html_gt;
        },

        // Multiple forms possible:
        //  A) output_url( dest, text, [ config_obj ] )
        //  B) output_url( dest, text, [ key1, val1, [...] ] )
        //  C) output_url( dest, [ config_obj ] )
        //  D) output_url( dest, [ key1, val1, [...] ] )
        output_url: function(dest) {
            var
                args_length = arguments.length,
                config = arguments[args_length - 1],
                text,
                key,
                value,
                start_i,
                a,
                len;

            // object properties hash, form A or C
            if (typeof config === "object") {
                text = (args_length === 3) ? arguments[1] : (config.html || dest);

                // Go ahead and clobber other stuff.
                if ("_type" in config && config._type === "offsite") {
                    config["class"] = "offsite";
                    config.target = "_blank";
                    delete config._type;
                }
            } else {
                config = {};

                if (args_length % 2) {
                    start_i = 1;
                } else {
                    text = arguments[1];
                    start_i = 2;
                }
                a = start_i;
                len = arguments.length;
                while (a < len) {
                    key = arguments[a];
                    value = arguments[++a];
                    if (key === "_type" && value === "offsite") {
                        config.target = "_blank";
                        config["class"] = "offsite";
                    } else {
                        config[key] = value;
                    }
                    a++;
                }

                if (!text) {
                    text = config.html || dest;
                }
            }

            var html = "<a href=\"" + dest + "\"";
            if (typeof config === "object") {
                for (key in config) {
                    html += " " + key + "=\"" + config[key] + "\"";
                }
            }
            html += ">" + text + "</a>";

            return html;
        },


        // Flattening argument lists in JS is much hairier than in Perl,
        // so this doesn't flatten array objects. Hopefully CLDR will soon
        // implement list_or; then we could deprecate this function.
        // cf. http://unicode.org/cldr/trac/ticket/4051
        list_separator: ", ",
        oxford_separator: ",",
        list_default_and: "&",
        list: function(word /* , [foo,bar,...] | foo, bar, ... */ ) {
            if (!word) {
                word = this.list_default_and;
            } // copying our Perl
            var list_sep = this.list_separator;
            var oxford_sep = this.oxford_separator;

            var the_list;
            if (typeof arguments[1] === "object" && arguments[1] instanceof Array) {
                the_list = arguments[1];
            } else {
                the_list = Array.prototype.concat.apply([], arguments).slice(1);
            }

            var len = the_list.length;

            if (!len) {
                return "";
            }

            if (len === 1) {
                return String(the_list[0]);
            } else if (len === 2) {
                return (the_list[0] + " " + word + " " + the_list[1]);
            } else {

                // Use slice() here to avoid altering the array
                // since it may have been passed in as an object.
                return (the_list.slice(0, -1).join(list_sep) + [oxford_sep, word, the_list.slice(-1)].join(" "));
            }
        },


        // This depends on locale-specific overrides of base functionality
        // but should not itself need an override.
        format_bytes: function(bytes, decimal_places) {
            if (decimal_places === undefined) {
                decimal_places = 2;
            }
            bytes = Number(bytes);
            var exponent = bytes && Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), data_abbreviations.length);
            if (!exponent) {

                // This is a special, internal-to-format_bytes, phrase: developers will not have to deal with this phrase directly.
                return this.maketext("[quant,_1,%s byte,%s bytes]", bytes); // the space between the '%s' and the 'b' is a non-break space (e.g. option-spacebar, not spacebar) // ## no extract maketext
                // We do not use &nbsp; or \u00a0 since:
                //   * parsers would need to know how to interpolate them in order to work with the phrase in the context of the system
                //   * the non-breaking space character behaves as you'd expect its various representations to.
                // Should a second instance of this sort of thing happen we can revisit the idea of adding [comment] in the phrase itself or perhaps supporting an embedded call to [output,nbsp].
            } else {

                // We use \u00a0 here because it won't affect lookup since it is not
                // being used in a source phrase and we don't want to worry about
                // whether an entity is going to be interpreted or not.
                return this.numf(bytes / Math.pow(1024, exponent), decimal_places) + "\u00a0" + data_abbreviations[exponent - 1];
            }
        },

        // CLDR-informed functions

        numerate: function(num) {
            if (this.get_plural_form) { // from CPAN Locales
                var numerated = this.get_plural_form.apply(this, arguments)[0];
                if (numerated === undefined) {
                    numerated = arguments[arguments.length - 1];
                }
                return numerated;
            } else { // English-language logic, in the absence of CLDR
                // The -1 case here is debatable.
                // cf. http://unicode.org/cldr/trac/ticket/4049
                var abs = Math.abs(num);

                if (abs === 1) {
                    return "" + arguments[1];
                } else if (abs === 0) {
                    return "" + arguments[arguments.length - 1];
                } else {
                    return "" + arguments[2];
                }
            }
        },
        quant: function(num) {
            var numerated, is_special_zero, decimal_places = 3;

            if (num instanceof Array) {
                decimal_places = num[1];
                num = num[0];
            }

            if (this.get_plural_form) { // from CPAN Locales
                var gpf = this.get_plural_form.apply(this, arguments);
                numerated = gpf[0];

                // If there's a mismatch between the actual number of forms
                // (singular, plural, etc.) and the real number, this can be
                // undefined, which can break code.  We pick the rightmost, or
                // "most plural," form as a fallback.
                if (numerated === undefined) {
                    numerated = arguments[arguments.length - 1];
                }
                is_special_zero = gpf[1];
            } else { // no CLDR, fall back to English
                numerated = this.numerate.apply(this, arguments);

                // Check: num is 0, we gave a special_zero value, and that numerate() gave it
                is_special_zero = (parseInt(num, 10) === 0) &&
                    (arguments.length > 3) &&
                    (numerated === String(arguments[3]));
            }

            var formatted = this.numf(num, decimal_places);

            if (numerated.indexOf("%s") !== -1) {
                return numerated.replace(/%s/g, formatted);
            }

            if (is_special_zero) {
                return numerated;
            }

            return this.is_rtl() ? (numerated + " " + formatted) : (formatted + " " + numerated);
        },

        _max_decimal_places: 6,
        numf: function(num, decimal_places) {
            if (decimal_places === undefined) {
                decimal_places = this._max_decimal_places;
            }

            // exponential -> don't know how to deal
            if (/e/.test(num)) {
                return String(num);
            }

            var cldr, decimal_format, decimal_group, decimal_decimal;
            try {
                cldr = this.get_cldr("misc_info").cldr_formats;
                decimal_format = cldr.decimal;
                decimal_group = cldr._decimal_format_group;
                decimal_decimal = cldr._decimal_format_decimal;
            } catch (e) {}

            // No CLDR, so fall back to hard-coded English values.
            if (!decimal_format || !decimal_group || !decimal_decimal) {
                decimal_format = "#,##0.###";
                decimal_group = ",";
                decimal_decimal = ".";
            }

            var is_negative = num < 0;
            num = Math.abs(num);

            // trim the decimal part to 6 digits and round
            var whole = Math.floor(num);
            var normalized, fraction;
            if (/(?!')\.(?!')/.test(num)) {

                // This weirdness is necessary to avoid floating-point
                // errors that can crop up with large-ish numbers.

                // Convert to a simple fraction.
                fraction = String(num).replace(/^[^.]+/, "0");

                // Now round to the desired precision.
                fraction = Number(fraction).toFixed(decimal_places);

                // e.g., 1.9999 when only 3 decimal places are desired.
                if (/^1/.test(fraction)) {
                    whole++;
                    num = whole;
                    fraction = undefined;
                } else {
                    fraction = fraction.replace(/^.*\./, "").replace(/0+$/, "");
                }

                normalized = Number(whole + "." + fraction);
            } else {
                normalized = num;
            }

            var pattern_with_outside_symbols;
            if (/(?!');(?!')/.test(decimal_format)) {
                pattern_with_outside_symbols = decimal_format.split(/(?!');(?!')/)[is_negative ? 1 : 0];
            } else {
                pattern_with_outside_symbols = (is_negative ? "-" : "") + decimal_format;
            }
            var inner_pattern = pattern_with_outside_symbols.match(/[0#].*[0#]/)[0];

            // Applying the integer part of the pattern is much easier if it's
            // done with the strings reversed.

            var pattern_split = inner_pattern.split(/(?!')\.(?!')/);
            var int_pattern_split = pattern_split[0].reverse().split(/(?!'),(?!')/);

            // If there is only one part of the int pattern, then set the "joiner"
            // to empty string. (http://unicode.org/cldr/trac/ticket/4094)
            var group_joiner;
            if (int_pattern_split.length === 1) {
                group_joiner = "";
            } else {

                // Most patterns look like #,##0.###, for which the leftmost # is
                // just a placeholder so we know where to put the group separator.
                int_pattern_split.pop();
                group_joiner = decimal_group;
            }

            var whole_reverse = String(whole).split("").reverse();
            var whole_assembled = []; // reversed
            var pattern;
            var replacer = function(chr) {
                switch (chr) {
                    case "#":
                        return whole_reverse.shift() || "";
                    case "0":
                        return whole_reverse.shift() || "0";
                }
            };
            while (whole_reverse.length) {
                if (int_pattern_split.length) {
                    pattern = int_pattern_split.shift();
                }

                // Since this is reversed, we can just replace a character
                // at a time, in regular forward order. Make sure we leave quoted
                // stuff alone while paying attention to stuff *by* quoted stuff.
                var assemble_chunk = pattern
                    .replace(/(?!')[0#]|[0#](?!')/g, replacer)
                    .replace(/'([.,0#;¤%E])'$/, "")
                    .replace(/'([.,0#;¤%E])'/, "$1");

                whole_assembled.push(assemble_chunk);
            }

            var formatted_num = whole_assembled.join(group_joiner).reverse() + (fraction ? decimal_decimal + fraction : "");
            return pattern_with_outside_symbols.replace(/[0#].*[0#]/, formatted_num);
        },

        list_and: function() {
            return this._list_join_cldr("list", arguments);
        },

        list_or: function() {
            return this._list_join_cldr("list_or", arguments);
        },

        _list_join_cldr: function(templates_name, args) {
            var the_list;
            if ((typeof args[0] === "object") && args[0] instanceof Array) {
                the_list = args[0].slice(0); // do not edit the values outside of this function
            } else if ((typeof args[0] === "object")) {
                if (args[0] instanceof Array) {
                    the_list = args.slice(0); // do not edit the values outside of this function
                } else {
                    the_list = [args[0]]; // do not edit the values outside of this function
                }
            } else if (typeof args === "object" && args[0] !== undefined) {
                if (args[0] instanceof Array) {
                    the_list = args[0].slice(0); // do not edit the values outside of this function
                } else {
                    the_list = [];
                    for (var k in args) {
                        the_list[k] = args[k];
                    }
                }
            }

            if (the_list === undefined) {
                the_list = [""];
            }

            var cldr_list;
            var len = the_list.length;
            var pattern;
            var text;

            try {
                cldr_list = this.get_cldr("misc_info").cldr_formats[templates_name];
            } catch (e) {
                var conjunction = (templates_name === "list_or") ? "or" : "and";

                cldr_list = {
                    2: "{0} " + conjunction + " {1}",
                    start: "{0}, {1}",
                    middle: "{0}, {1}",
                    end: "{0}, " + conjunction + " {1}",
                };
            }

            var replacer = function(str, p1) {
                switch (p1) {
                    case "0":
                        return text;
                    case "1":
                        return the_list[i++];
                }
            };

            switch (len) {
                case 0:
                    return;
                case 1:
                    return String(the_list[0]);
                default:
                    if (len === 2) {
                        text = cldr_list["2"];
                    } else {
                        text = cldr_list.start;
                    }

                    text = text.replace(/\{([01])\}/g, function(all, bit) {
                        return the_list[bit];
                    });
                    if (len === 2) {
                        return text;
                    }

                    var i = 2;
                    while (i < len) {
                        pattern = cldr_list[(i === len - 1) ? "end" : "middle"];

                        text = pattern.replace(/\{([01])\}/g, replacer);
                    }

                    return text;
            }
        },

        list_and_quoted: function() {
            return this._list_quoted("list_and", arguments);
        },
        list_or_quoted: function() {
            return this._list_quoted("list_or", arguments);
        },

        // This *may* be useful publicly.
        _quote: function(str) {
            var delimiters;
            try {
                delimiters = this.get_cldr("misc_info").delimiters;
            } catch (e) {
                delimiters = {
                    quotation_start: "“",
                    quotation_end: "”",
                };
            }
            return delimiters["quotation_start"] + str + delimiters["quotation_end"];
        },

        _list_quoted: function(join_fn, args) {
            var the_list;
            if (typeof (args[0]) === "object") {
                if (args[0] instanceof Array) {

                    // slice() so that we don’t change the caller’s data
                    the_list = args[0].slice();
                } else {
                    throw ( "Unrecognized list_and_quoted() argument: " + args[0].toString() );
                }
            } else {
                the_list = Array.prototype.slice.apply(args);
            }

            // Emulate Locales.pm _quote_get_list_items() list_quote_mode 'all'.
            // list_or(), currently not implemented in JS (no reason for it not to be), will need to behave the same
            if (the_list === undefined || the_list.length === 0) {

                the_list = [""]; // disambiguate no args
            }

            var locale = this;
            return this[join_fn](the_list.map( function() {
                return locale._quote.apply(locale, arguments);
            } ) );
        },

        local_datetime: function(my_date, format_string) {
            if (!this._cldr) {
                return this.datetime.apply(this, arguments);
            }

            if (my_date instanceof Date) {
                my_date = new Date(my_date);
            } else if (/^-?\d+$/.test(my_date)) {
                my_date = new Date(my_date * 1000);
            } else {
                my_date = new Date();
            }

            var tz_offset = my_date.getTimezoneOffset();

            my_date.setMinutes(my_date.getMinutes() - tz_offset);

            var non_utc = this.datetime(my_date, format_string);

            // This is really hackish...but should be safe.
            if (non_utc.indexOf("UTC") > -1) {
                var hours = (tz_offset > 0) ? "-" : "+";
                hours += Math.floor(Math.abs(tz_offset) / 60).toString().lpad(2, "0");
                var minutes = (tz_offset % 60).toString().lpad(2, "0");
                non_utc = non_utc.replace("UTC", "GMT" + hours + minutes);
            }

            return non_utc;
        },

        // time can be either epoch seconds or a JS Date object
        // format_string can match the regexp below or be a [ date, time ] suffix pair
        // (e.g., [ "medium", "short" ] -> "Aug 30, 2011 5:12 PM")
        datetime: function datetime(my_date, format_string) {
            if (!my_date && (my_date !== 0)) {
                my_date = new Date();
            } else if (!(my_date instanceof Date)) {
                my_date = new Date(my_date * 1000);
            }

            var loc_strs = this.get_cldr("datetime");

            if (!loc_strs) {
                return my_date.toString();
            }

            if (format_string) {

                // Make sure we don't just grab any random CLDR datetime key.
                if (/^(?:date|time|datetime|special)_format_/.test(format_string)) {
                    format_string = loc_strs[format_string];
                }
            } else {
                format_string = loc_strs.date_format_long;
            }

            var substituter = function() {

                // Check for quoted strings
                if (arguments[1]) {
                    return arguments[1].substr( 1, arguments[1].length - 2 );
                }

                // No quoted string, eh? OK, let’s check for a known pattern.
                var key = arguments[2];
                var xformed = (function() {
                    switch (key) {
                        case "yy":
                            return Math.abs(my_date.getUTCFullYear()).toString().slice(-2);
                        case "y":
                        case "yyy":
                        case "yyyy":
                            return Math.abs(my_date.getUTCFullYear());
                        case "MMMMM":
                            return loc_strs.month_format_narrow[my_date.getUTCMonth()];
                        case "LLLLL":
                            return loc_strs.month_stand_alone_narrow[my_date.getUTCMonth()];
                        case "MMMM":
                            return loc_strs.month_format_wide[my_date.getUTCMonth()];
                        case "LLLL":
                            return loc_strs.month_stand_alone_wide[my_date.getUTCMonth()];
                        case "MMM":
                            return loc_strs.month_format_abbreviated[my_date.getUTCMonth()];
                        case "LLL":
                            return loc_strs.month_stand_alone_abbreviated[my_date.getUTCMonth()];
                        case "MM":
                        case "LL":
                            return (my_date.getUTCMonth() + 1).toString().lpad(2, "0");
                        case "M":
                        case "L":
                            return my_date.getUTCMonth() + 1;
                        case "EEEE":
                            return loc_strs.day_format_wide[ get_cldr_day(my_date) ];
                        case "EEE":
                        case "EE":
                        case "E":
                            return loc_strs.day_format_abbreviated[ get_cldr_day(my_date) ];
                        case "EEEEE":
                            return loc_strs.day_format_narrow[ get_cldr_day(my_date) ];
                        case "cccc":
                            return loc_strs.day_stand_alone_wide[ get_cldr_day(my_date) ];
                        case "ccc":
                        case "cc":
                        case "c":
                            return loc_strs.day_stand_alone_abbreviated[ get_cldr_day(my_date) ];
                        case "ccccc":
                            return loc_strs.day_stand_alone_narrow[ get_cldr_day(my_date) ];
                        case "dd":
                            return my_date.getUTCDate().toString().lpad(2, "0");
                        case "d":
                            return my_date.getUTCDate();
                        case "h":
                        case "hh":
                            var twelve_hours = my_date.getUTCHours();
                            if (twelve_hours > 12) {
                                twelve_hours -= 12;
                            }
                            if (twelve_hours === 0) {
                                twelve_hours = 12;
                            }
                            return (key === "hh") ? twelve_hours.toString().lpad(2, "0") : twelve_hours;
                        case "H":
                            return my_date.getUTCHours();
                        case "HH":
                            return my_date.getUTCHours().toString().lpad(2, "0");
                        case "m":
                            return my_date.getUTCMinutes();
                        case "mm":
                            return my_date.getUTCMinutes().toString().lpad(2, "0");
                        case "s":
                            return my_date.getUTCSeconds();
                        case "ss":
                            return my_date.getUTCSeconds().toString().lpad(2, "0");
                        case "a":
                            var hours = my_date.getUTCHours();
                            if (hours < 12) {
                                return loc_strs.am_pm_abbreviated[0];
                            } else if (hours > 12) {
                                return loc_strs.am_pm_abbreviated[1];
                            }

                            // CLDR defines "noon", but CPAN DateTime::Locale doesn't have it.
                            return loc_strs.am_pm_abbreviated[1];
                        case "z":
                        case "zzzz":
                        case "v":
                        case "vvvv":
                            return "UTC";
                        case "G":
                        case "GG":
                        case "GGG":
                            return loc_strs.era_abbreviated[my_date.getUTCFullYear() < 0 ? 0 : 1];
                        case "GGGGG":
                            return loc_strs.era_narrow[my_date.getUTCFullYear() < 0 ? 0 : 1];
                        case "GGGG":
                            return loc_strs.era_wide[my_date.getUTCFullYear() < 0 ? 0 : 1];
                    }

                    if (window.console) {
                        console.warn("Unknown CLDR date/time pattern: " + key + " (" + format_string + ")" );
                    }
                    return key;
                })();

                return xformed;
            };

            return format_string.replace(
                /('[^']+')|(([a-zA-Z])\3*)/g,
                substituter
            );
        },

        is_rtl: function() {
            try {
                return this.get_cldr("misc_info").orientation.characters === "right-to-left";
            } catch (e) {
                return false;
            }
        },

        /**
         * Shorten a string into one or two end fragments, using CLDR formatting.
         *
         * ex.: elide( "123456", 2 )    //"12…"
         * ex.: elide( "123456", 2, 2 ) //"12…56"
         * ex.: elide( "123456", 0, 2 ) //"…56"
         *
         * @param str     {String} The actual string to shorten.
         * @param start_length {Number} How many initial characters to put into the result.
         * @param end_length {Number} How many final characters to put into the result. (optional)
         * @return        {String} The processed string.
         */
        elide: function(str, start_length, end_length) {
            start_length = start_length || 0;
            end_length = end_length || 0;

            if (str.length <= (start_length + end_length)) {
                return str;
            }

            var template, substring0, substring1;
            if (start_length) {
                if (end_length) {
                    template = "medial";
                    substring0 = str.substr(0, start_length);
                    substring1 = str.substr(str.length - end_length);
                } else {
                    template = "final";
                    substring0 = str.substr(0, start_length);
                }
            } else if (end_length) {
                template = "initial";
                substring0 = str.substr(str.length - end_length);
            } else {
                return "";
            }

            try {
                template = this._cldr.misc_info.cldr_formats.ellipsis[template]; // JS reserved word
            } catch (e) {
                template = DEFAULT_ELLIPSIS[template];
            }

            if (substring1) { // medial
                return template
                    .replace("{0}", substring0)
                    .replace("{1}", substring1);
            }

            return template.replace("{0}", substring0);
        },

        get_first_day_of_week: function() {
            var fd = Number(this.get_cldr("datetime").first_day_of_week) + 1;
            return (fd === 8) ? 0 : fd;
        },

        set_cldr: function(cldr) {
            var cldr_obj = this._cldr;
            if (!cldr_obj) {
                cldr_obj = this._cldr = {};
            }
            for (var key in cldr) {
                cldr_obj[key] = cldr[key];
            }
        },

        get_cldr: function(key) {
            if (!this._cldr) {
                return;
            }

            if ((typeof key === "object") && (key instanceof Array)) {
                return key.map(this.get_cldr, this);
            } else {
                return key ? this._cldr[key] : this._cldr;
            }
        },

        // For testing. Don't "delete" since this will cause prototype traversal.
        reset_cldr: function() {
            this._cldr = undefined;
        },

        _cldr: null,
    };

    /**
     * Generate a new locale from the various CLDR data passed in.
     *
     * @param  {String} tag            Locale tag name.
     * @param  {Object} functionsMixin Collection of functions to mix into the locale class passed from the CLDR data.
     * @param  {Object} dateTimeInfo   Datetime specific formatting information for the locale
     * @param  {Object} miscInfo       Miscellaneous formatting information for the locale.
     * @return {Object}                Reference to the locale just added.
     */
    CPANEL.Locale.generateClassFromCldr = function(tag, functionsMixin, dateTimeInfo, miscInfo) {
        if (CPANEL.Locale._locales[tag]) {

            // Already generated
            return Locale._locales[tag];
        }

        // Create a custom class for the locale generated from the CLDR data.
        var GeneratedLocale = function() {
            GeneratedLocale.superclass.constructor.apply(this, arguments);
            this.set_cldr( { datetime: dateTimeInfo } );
            this.set_cldr( { misc_info: miscInfo } );
        };

        // Mix in the base Locale and the CLDR locale functions into the new class.
        YAHOO.lang.extend( GeneratedLocale, CPANEL.Locale, functionsMixin );

        // Add the new locale class to the collection
        Locale.add_locale(tag, GeneratedLocale);

        // Update the locale handle since this is the most likey use case
        window.LOCALE = CPANEL.Locale.get_handle();

        return CPANEL.Locale._locales[tag];
    };


    for (var key in prototype_stuff) {
        Locale.prototype[key] = prototype_stuff[key];
    }

    // This will be overwritten in minified code.
    window.LOCALE = Locale.get_handle();

})(window);

//--- end /usr/local/cpanel/base/cjt/locale.js ---

//--- start /usr/local/cpanel/base/cjt/icons.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including icons.js!");
} else {

    /**
    The icons module contains properties that reference icons for our product.
    @module icons
*/

    /**
    The icons class contains properties that reference icons for our product.
    @class icons
    @namespace CPANEL
    @extends CPANEL
*/
    CPANEL.icons = {

        /** /cPanel_magic_revision_XXXXX/ is used to allow caching of images -- XXXXX needs to be incremented when the image changes **/

        /**
        Error icon located at cjt/images/icons/error.png
        @property error
        @type string
    */
        error: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/error.png" width="16" height="16" alt="error" />',
        error_src: "/cPanel_magic_revision_0/cjt/images/icons/error.png",
        error24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/error24.png" width="24" height="24" alt="error" />',
        error24_src: "/cPanel_magic_revision_0/cjt/images/icons/error24.png",

        /**
        success icon located at cjt/images/icons/success.png
        @property success
        @type string
    */
        success: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/success.png" alt="success" width="16" height="16" />',
        success_src: "/cPanel_magic_revision_0/cjt/images/icons/success.png",
        success24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/success24.png" alt="success" width="24" height="24" />',
        success24_src: "/cPanel_magic_revision_0/cjt/images/icons/success24.png",

        /**
        unknown icon located at cjt/images/icons/unknown.png
        @property unknown
        @type string
    */
        unknown: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/unknown.png" alt="unknown" width="16" height="16" />',
        unknown_src: "/cPanel_magic_revision_0/cjt/images/icons/unknown.png",
        unknown24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/unknown24.png" alt="unknown" width="24" height="24" />',
        unknown24_src: "/cPanel_magic_revision_0/cjt/images/icons/unknown24.png",

        /**
        warning icon located at cjt/images/icons/warning.png
        @property warning
        @type string
    */
        warning: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/warning.png" alt="warning" width="16" height="16"/>',
        warning_src: "/cPanel_magic_revision_0/cjt/images/icons/warning.png",
        warning24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/warning24.png" alt="warning" width="24" height="24"/>',
        warning24_src: "/cPanel_magic_revision_0/cjt/images/icons/warning24.png",

        /**
        AJAX loading icon located at cjt/images/ajax-loader.gif
        @property ajax
        @type string
    */
        ajax: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/loading.gif" alt="loading" />',
        ajax_src: "/cPanel_magic_revision_0/cjt/images/loading.gif",

        // /cjt/images/1px_transparent.gif
        transparent: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/1px_transparent.gif" alt="" width="1" height="1"/>',
        transparent_src: "/cPanel_magic_revision_0/cjt/images/1px_transparent.gif",

        // /cjt/images/rejected.png
        rejected: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/rejected.png" alt="rejected" width="16" height="16"/>',
        rejected_src: "/cPanel_magic_revision_0/cjt/images/rejected.png",
        rejected24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/rejected24.png" alt="rejected" width="24" height="24"/>',
        rejected24_src: "/cPanel_magic_revision_0/cjt/images/rejected24.png",

        // /base/yui/container/assets/info16_1.gif
        info: '<img align="absmiddle" src="/cPanel_magic_revision_0/yui/container/assets/info16_1.gif" alt="" width="16" height="16"/>',
        info_src: "/cPanel_magic_revision_0/yui/container/assets/info16_1.gif",

        // /cjt/images/filtered.png
        filtered: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/filter.png" alt="" width="16" height="16"/>',
        filtered_src: "/cPanel_magic_revision_0/cjt/images/filtered.png",
        filtered24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/filter24.png" alt="" width="24" height="24"/>',
        filtered24_src: "/cPanel_magic_revision_0/cjt/images/filtered24.png",

        // /cjt/images/archive.png
        archive: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/archive.png" alt="" width="16" height="16"/>',
        archive_src: "/cPanel_magic_revision_0/cjt/images/archive.png",
        archive24: '<img align="absmiddle" src="/cPanel_magic_revision_0/cjt/images/icons/archive24.png" alt="" width="24" height="24"/>',
        archive24_src: "/cPanel_magic_revision_0/cjt/images/archive24.png"

    }; // end icons object
} // end else statement

//--- end /usr/local/cpanel/base/cjt/icons.js ---

//--- start /usr/local/cpanel/base/cjt/animate.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0 */

var CPANEL = window.CPANEL,
    YAHOO = window.YAHOO;

// check to be sure the CPANEL global object already exists
if (typeof CPANEL === "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including animate.js!");
} else if (typeof YAHOO.util.Anim === "undefined" || !YAHOO.util.Anim) {

    // check to be sure the YUI Animation library exists
    alert("You must include the YUI Animation library before including animate.js!");
} else {

    /**
    The animate module contains methods for animation.
    @module animate
*/

    (function() {

        // To prevent a slide or fade from starting in the middle of one
        // that's already in progress. Some optimizations here; modify with care.
        var _SLIDING = [];
        var _FADING = [];
        var i, cur_el;

        function _check(el, to_check) {
            for (i = 0; cur_el = to_check[i++]; /* nothing */ ) {
                if (cur_el === el) {
                    return false; // abort slide/fade
                }
            }
            to_check.push(el);

            return true;
        }

        function _done_check(el, to_check) {
            for (i = 0; cur_el = to_check[i++]; /* nothing */ ) {
                if (cur_el === el) {
                    return to_check.splice(--i, 1);
                }
            }

            return;
        }

        var WHM_NAVIGATION_TOP_CONTAINER_SELECTOR = "#navigation #breadcrumbsContainer";

        CPANEL.animate = {

            // animate the margins, borders, paddings, and height sequentially,
            // rather than animating them concurrently;
            // concurrent slide produces an unattractive "slide within a slide" that
            // sequential slide avoids, but it's jerky on most machines/browsers in 2010.
            // Set this to true in 2012 or so. Hopefully. :)
            sequential_slide: false,

            // Enable this to get useful console notices.
            debug: false,

            // Opts:
            //  expand_width: sets -10000px right margin when reading computed height;
            //      this is for when the animated element's container width influences
            //      computed height (e.g., if both container and animated element are
            //      absolutely positioned).
            slide_down: function(elem, opts) {
                var callback = (typeof opts === "function") && opts;
                var expand_width = opts && opts.expand_width;

                var el = DOM.get(elem);
                var check = _check(el, _SLIDING);
                if (!check) {
                    return;
                }

                var s = el.style;

                var old_position = s.position;
                var old_visibility = s.visibility;
                var old_overflow = s.overflow;
                var old_bottom = s.bottom; // See case 45653 for why this is needed.
                var old_display = DOM.getStyle(el, "display");

                // Set the right margin in case we slide something down in an
                // absolutely-positioned, flexibly-sized container; the wide right margin
                // will make the sliding-down element expand to its full width
                // when we read the attributes below.
                if (expand_width) {
                    var old_right_margin = s.marginRight;
                    s.marginRight = "-10000px";
                }

                var change_overflow = old_overflow !== "hidden";
                var change_position = old_position !== "absolute";
                var change_visibility = old_visibility !== "hidden";

                // guess at what kind of display to use
                var test_node = document.createElement(el.nodeName);
                test_node.style.position = "absolute";
                test_node.style.visibility = "hidden";
                document.body.appendChild(test_node);
                var default_display = DOM.getStyle(test_node, "display");
                document.body.removeChild(test_node);
                delete test_node;

                if (change_visibility) {
                    s.visibility = "hidden";
                }
                if (change_position) {
                    s.position = "absolute";
                }
                s.bottom = 0;
                if (change_overflow) {
                    s.overflow = "hidden";
                }
                s.display = default_display;

                var old_box_attrs = CPANEL.animate._get_box_attributes(el);
                var computed_box_attrs = CPANEL.animate._get_computed_box_attributes(el);


                var finish_up = function() {
                    for (var attr in computed_box_attrs) {
                        el.style[attr] = old_box_attrs[attr] || "";
                    }

                    if (change_overflow) {
                        s.overflow = old_overflow;
                    }
                    if (old_display !== "none") {
                        s.display = old_display;
                    }
                    _done_check(el, _SLIDING);
                };

                if (change_position) {
                    s.position = old_position;
                }
                s.bottom = old_bottom;
                if (change_visibility) {
                    s.visibility = old_visibility;
                }
                if (expand_width) {
                    s.marginRight = old_right_margin;
                }

                for (var attr in computed_box_attrs) {
                    s[attr] = 0;
                }

                if (CPANEL.animate.debug) {
                    console.debug("slide down", el, computed_box_attrs);
                }

                if (CPANEL.animate.sequential_slide) {
                    var total_slide_distance = 0;
                    for (var attr in computed_box_attrs) {
                        total_slide_distance += computed_box_attrs[attr];
                    }

                    var animations = [];
                    var all_animations = CPANEL.animate._animation_order;
                    var all_animations_count = CPANEL.animate._animation_order.length;
                    var last_animation;
                    for (var a = 0; a < all_animations_count; a++) {
                        var attr = all_animations[a];
                        if (attr in computed_box_attrs) {
                            var slide_distance = computed_box_attrs[attr];
                            var slide_time = CPANEL.animate.slideTime * slide_distance / total_slide_distance;
                            var anims = {};
                            anims[attr] = {
                                from: 0,
                                to: computed_box_attrs[attr]
                            };
                            var cur_anim = new YAHOO.util.Anim(el, anims, slide_time);
                            if (last_animation) {
                                (function(frozen_anim_obj) {
                                    var next_trigger = function() {
                                        frozen_anim_obj.animate();
                                    };
                                    last_animation.onComplete.subscribe(next_trigger);
                                })(cur_anim);
                            }
                            animations.push(cur_anim);
                            last_animation = cur_anim;
                        }
                    }
                    last_animation.onComplete.subscribe(finish_up);
                    if (callback) {
                        last_animation.onComplete.subscribe(callback);
                    }

                    animations[0].animate();

                    return animations;
                } else {
                    var animations = {};
                    for (var attr in computed_box_attrs) {
                        animations[attr] = {
                            from: 0,
                            to: computed_box_attrs[attr]
                        };
                    }

                    var anim = new YAHOO.util.Anim(elem, animations, CPANEL.animate.slideTime);

                    anim.onComplete.subscribe(finish_up);
                    if (callback) {
                        anim.onComplete.subscribe(callback);
                    }

                    anim.animate();

                    return anim;
                }
            },
            slide_up: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _SLIDING);
                if (!el || !check) {
                    return;
                }

                var s = el.style;

                old_overflow = s.overflow;
                var change_overflow = old_overflow !== "hidden";

                if (change_overflow) {
                    s.overflow = "hidden";
                }

                var old_box_settings = CPANEL.animate._get_box_attributes(el);
                var computed_box_settings = CPANEL.animate._get_computed_box_attributes(el);

                var finish_up = function() {
                    for (var attr in computed_box_settings) {
                        s[attr] = old_box_settings[attr] || "";
                    }

                    s.display = "none";
                    if (change_overflow) {
                        s.overflow = old_overflow;
                    }

                    _done_check(el, _SLIDING);
                };

                if (CPANEL.animate.sequential_slide) {
                    var total_slide_distance = 0;
                    for (var attr in computed_box_settings) {
                        total_slide_distance += computed_box_settings[attr];
                    }
                    var animations = [];
                    var all_animations = CPANEL.animate._animation_order;
                    var all_animations_count = CPANEL.animate._animation_order.length;
                    var last_animation;
                    for (var a = all_animations_count - 1; a > -1; a--) {
                        var attr = all_animations[a];
                        if (attr in computed_box_settings) {
                            var slide_distance = computed_box_settings[attr];
                            var slide_time = CPANEL.animate.slideTime * slide_distance / total_slide_distance;
                            var anims = {};
                            anims[attr] = {
                                to: 0
                            };
                            var cur_anim = new YAHOO.util.Anim(el, anims, slide_time);
                            if (last_animation) {
                                (function(frozen_anim_obj) {
                                    var next_trigger = function() {
                                        frozen_anim_obj.animate();
                                    };
                                    last_animation.onComplete.subscribe(next_trigger);
                                })(cur_anim);
                            }
                            animations.push(cur_anim);
                            last_animation = cur_anim;
                        }
                    }
                    last_animation.onComplete.subscribe(finish_up);
                    if (callback) {
                        last_animation.onComplete.subscribe(callback);
                    }

                    animations[0].animate();

                    return animations;
                } else {
                    var animations = {};

                    for (var attr in computed_box_settings) {
                        animations[attr] = {
                            to: 0
                        };
                    }

                    var anim = new YAHOO.util.Anim(el, animations, CPANEL.animate.slideTime);

                    anim.onComplete.subscribe(finish_up);
                    if (callback) {
                        anim.onComplete.subscribe(callback);
                    }
                    anim.animate();

                    return anim;
                }
            },

            slide_up_and_empty: function(elem, callback) {
                return CPANEL.animate.slide_up(elem, function() {
                    var that = this;
                    if (callback) {
                        callback.call(that);
                    }
                    this.getEl().innerHTML = "";
                });
            },
            slide_up_and_remove: function(elem, callback) {
                return CPANEL.animate.slide_up(elem, function() {
                    var that = this;
                    if (callback) {
                        callback.call(that);
                    }
                    var el = this.getEl();
                    el.parentNode.removeChild(el);
                });
            },
            slide_toggle: function(elem, callback) {
                var el = DOM.get(elem);
                var func_name = el.offsetHeight ? "slide_up" : "slide_down";
                return CPANEL.animate[func_name](el, callback);
            },

            _box_attributes: {
                height: "height",
                paddingTop: "padding-top",
                paddingBottom: "padding-bottom",
                borderTopWidth: "border-top-width",
                borderBottomWidth: "border-bottom-width",
                marginTop: "margin-top",
                marginBottom: "margin-bottom"
            },
            _animation_order: [ // for sliding down
                "marginTop", "borderTopWidth", "paddingTop",
                "height",
                "paddingBottom", "borderBottomWidth", "marginBottom"
            ],
            _get_box_attributes: function(el) {
                var attrs = CPANEL.util.keys(CPANEL.animate._box_attributes);
                var attrs_count = attrs.length;
                var el_box_attrs = {};
                for (var a = 0; a < attrs_count; a++) {
                    var cur_attr = attrs[a];
                    var attr_val = el.style[attrs[a]];
                    if (attr_val != "") {
                        el_box_attrs[cur_attr] = attr_val;
                    }
                }
                return el_box_attrs;
            },
            _get_computed_box_attributes: function(el) {
                var computed_box_attrs = {};
                var attr_map = CPANEL.animate._box_attributes;
                for (var attr in attr_map) {
                    var computed = parseFloat(DOM.getStyle(el, attr_map[attr]));
                    if (computed > 0) {
                        computed_box_attrs[attr] = computed;
                    }
                }

                // in case height is "auto"
                if (!("height" in computed_box_attrs)) {
                    var simple_height = el.offsetHeight;
                    if (simple_height) {
                        for (var attr in computed_box_attrs) {
                            if (attr !== "marginTop" && attr !== "marginBottom") {
                                simple_height -= computed_box_attrs[attr];
                            }
                        }
                        if (simple_height) {
                            computed_box_attrs.height = simple_height;
                        }
                    }
                }
                return computed_box_attrs;
            },

            fade_in: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _FADING);
                if (!check) {
                    return;
                }

                var old_filter = "",
                    element_style_opacity = "";
                if ("opacity" in el.style) {
                    element_style_opacity = el.style.opacity;
                } else {
                    var old_filter = el.style.filter;
                }

                var target_opacity = parseFloat(DOM.getStyle(el, "opacity"));

                var anim = new YAHOO.util.Anim(el, {
                    opacity: {
                        to: target_opacity || 1
                    }
                }, CPANEL.animate.fadeTime);

                anim.onComplete.subscribe(function() {
                    if ("opacity" in el.style) {
                        el.style.opacity = element_style_opacity;
                    } else if (old_filter) {
                        el.style.filter = old_filter;
                    }

                    _done_check(el, _FADING);
                });
                if (callback) {
                    anim.onComplete.subscribe(callback);
                }
                DOM.setStyle(el, "opacity", 0);
                el.style.visibility = "";
                if (el.style.display === "none") {
                    el.style.display = "";
                }
                anim.animate();
                return anim;
            },
            fade_out: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _FADING);
                if (!check) {
                    return;
                }
                var old_opacity = el.style.opacity;

                var anim = new YAHOO.util.Anim(el, {
                    opacity: {
                        to: 0
                    }
                }, CPANEL.animate.fadeTime);

                anim.onComplete.subscribe(function() {
                    el.style.display = "none";
                    el.style.opacity = old_opacity;

                    _done_check(el, _FADING);
                });
                if (callback) {
                    anim.onComplete.subscribe(callback);
                }
                anim.animate();
                return anim;
            },
            fade_toggle: function(elem, callback) {
                var el = DOM.get(elem);
                var func_name = el.offsetHeight ? "fade_out" : "fade_in";
                return CPANEL.animate[func_name](el, callback);
            },

            slideTime: 0.2,
            fadeTime: 0.32,

            /**
                Returns the browser-computed "auto" height of an element.<br />
                It calculates the height by changing the style of the element: opacity: 100%; z-index: 5000; display: block, height: auto<br />
                Then it grabs the height of the element in that state and returns the original style attributes.<br />
                This function is used by animation functions to determine the height to animate to.<br />
                NOTE: the height does NOT include padding-top or padding-bottom; only the actual height of the element
                @method getAutoHeight
                @param {DOM element} el a reference to a DOM element, will get passed to YAHOO.util.Dom.get
                @return {integer} the "auto" height of the element
            */
            getAutoHeight: function(elid) {

                // get the element
                el = YAHOO.util.Dom.get(elid);

                // copy the current style
                var original_opacity = YAHOO.util.Dom.getStyle(el, "opacity");
                var original_zindex = YAHOO.util.Dom.getStyle(el, "z-index");
                var original_display = YAHOO.util.Dom.getStyle(el, "display");
                var original_height = YAHOO.util.Dom.getStyle(el, "height");

                // make the element invisible and expand it to it's auto height
                YAHOO.util.Dom.setStyle(el, "opacity", 1);
                YAHOO.util.Dom.setStyle(el, "z-index", 5000);
                YAHOO.util.Dom.setStyle(el, "display", "block");
                YAHOO.util.Dom.setStyle(el, "height", "auto");

                // grab the height of the element
                var currentRegion = YAHOO.util.Dom.getRegion(el);
                var padding_top = parseInt(YAHOO.util.Dom.getStyle(el, "padding-top"));
                var padding_bottom = parseInt(YAHOO.util.Dom.getStyle(el, "padding-bottom"));
                var currentHeight = (currentRegion.bottom - currentRegion.top - padding_top - padding_bottom);

                // return the original style
                var original_opacity = YAHOO.util.Dom.setStyle(el, "opacity", original_opacity);
                var original_zindex = YAHOO.util.Dom.setStyle(el, "z-index", original_zindex);
                var original_display = YAHOO.util.Dom.setStyle(el, "display", original_display);
                var original_height = YAHOO.util.Dom.setStyle(el, "height", original_height);

                return currentHeight;
            }
        }; // end animate object


        if (!("ContainerEffect" in CPANEL.animate)) {
            CPANEL.animate.ContainerEffect = {};
        }
        var _get_style = YAHOO.util.Dom.getStyle;
        var _set_style = YAHOO.util.Dom.setStyle;
        var Config = YAHOO.util.Config;

        var _mask;
        var _get_mask_opacity = function() {
            if (!("_mask_opacity" in this)) {
                _mask = this.mask;
                this._mask_opacity = _get_style(_mask, "opacity");
                _set_style(_mask, "opacity", 0);
            }
        };

        var FADE_MODAL = function(ovl, dur) {
            var fade = YAHOO.widget.ContainerEffect.FADE.apply(this, arguments);

            if (!Config.alreadySubscribed(ovl.beforeShowMaskEvent, _get_mask_opacity, ovl)) {
                ovl.beforeShowMaskEvent.subscribe(_get_mask_opacity);
            }

            fade.animIn.onStart.subscribe(function() {
                if (ovl.mask) {
                    var anim = new YAHOO.util.Anim(ovl.mask, {
                        opacity: {
                            from: 0,
                            to: ovl._mask_opacity
                        }
                    }, dur);

                    // So the next _get_mask_opacity() will run.
                    delete this._mask_opacity;

                    anim.animate();
                }
            });
            fade.animOut.onStart.subscribe(function() {
                if (ovl.mask) {
                    var anim = new YAHOO.util.Anim(ovl.mask, {
                        opacity: {
                            to: 0
                        }
                    }, dur);
                    anim.animate();
                }
            });
            fade.animOut.onComplete.subscribe(function() {
                if (ovl.mask) {
                    DOM.setStyle(ovl.mask, "opacity", 0);
                }
            });

            return fade;
        };
        CPANEL.animate.ContainerEffect.FADE_MODAL = FADE_MODAL;

        // FADE_MODAL works by attaching a listener to the beforeShowMask event.
        // We need to remove that listener every time we set a new "effect" so that
        // any listener from FADE_MODAL won't affect the next one.
        var _configEffect = YAHOO.widget.Overlay.prototype.configEffect;
        YAHOO.widget.Overlay.prototype.configEffect = function() {
            if (this.beforeShowMaskEvent) {
                this.beforeShowMaskEvent.unsubscribe(_get_mask_opacity);
            }
            return _configEffect.apply(this, arguments);
        };


        // CPANEL.animate.Rotation
        // extension of YAHOO.util.Anim
        // attributes are just "from", "to", and "unit"
        // not super-complete...but it works in IE :)
        //
        // Notable limitation: The IE code assumes the rotating object is stationary.
        // It would be possible to adjust this code to accommodate objects that move
        // while rotating, but it would be "jaggier" and might interfere with the
        // other animation.
        var _xform_attrs = ["transform", "MozTransform", "WebkitTransform", "OTransform", "msTransform"];
        var _transform_attribute = null;
        var _test_style = (document.body || document.createElement("span")).style;
        for (var a = 0, cur_a; cur_a = _xform_attrs[a++]; /* */ ) {
            if (cur_a in _test_style) {
                _transform_attribute = cur_a;
                break;
            }
        }
        if (!_transform_attribute) {
            var ie_removeProperty = "removeProperty" in _test_style ? "removeProperty" : "removeAttribute";

            var half_pi = 0.5 * Math.PI;
            var pi = Math.PI;
            var pi_and_half = 1.5 * Math.PI;
            var two_pi = 2 * Math.PI;

            var abs = Math.abs;
            var sin = Math.sin;
            var cos = Math.cos;
        }

        var _rotate_regexp = /rotate\(([^\)]*)\)/;
        var _unit_conversions = {
            deg: {
                grad: 10 / 9,
                rad: Math.PI / 180,
                deg: 1
            },
            grad: {
                deg: 9 / 10,
                rad: Math.PI / 200,
                grad: 1
            },
            rad: {
                deg: 180 / Math.PI,
                grad: 200 / Math.PI,
                rad: 1
            }
        };

        var Rotation = function() {
            if (arguments[0]) {
                Rotation.superclass.constructor.apply(this, arguments);

                // IE necessitates a few workarounds:
                // 1) Since IE rotates "against the upper-left corner", move the element
                //   on each rotation to where it needs to be so it looks like we rotate
                //   from the center.
                // 2) Since IE doesn't remove an element from the normal flow when it rotates.
                //   create a clone of the object, make it position:absolute, and rotate that.
                //   This will produce a "jerk" if the rotation isn't to/from 0/180 degrees.
                if (!_transform_attribute) {
                    var el = YAHOO.util.Dom.get(arguments[0]);
                    var _old_visibility;
                    var _clone_el;
                    var _old_position;
                    var _top_style;
                    var _left_style;

                    this.onStart.subscribe(function() {
                        _top_style = el.style.top;
                        _left_style = el.style.left;

                        // setting any "zoom" property forces hasLayout
                        // without currentStyle.hasLayout, no filter controls display
                        if (!el.currentStyle.hasLayout) {
                            if (DOM.getStyle(el, "display") === "inline") {
                                el.style.display = "inline-block";
                            } else {
                                el.style.zoom = "1";
                            }
                        }

                        // The clone is needed:
                        // 1. When rotating an inline element (to maintain the layout)
                        // 2. When not rotating from a vertical
                        // ...but for simplicity, this code always creates the clone.
                        _clone_el = el.cloneNode(true);

                        _clone_el.id = "";
                        _clone_el.style.visibility = "hidden";
                        _clone_el.style.position = "absolute";
                        el.parentNode.insertBefore(_clone_el, el);

                        if (_clone_el.style.filter) {
                            _clone_el.style.filter = "";
                        }
                        var region = YAHOO.util.Dom.getRegion(_clone_el);
                        var width = parseFloat(YAHOO.util.Dom.getStyle(_clone_el, "width")) || region.width;
                        var height = parseFloat(YAHOO.util.Dom.getStyle(_clone_el, "height")) || region.height;
                        this._center_x = width / 2;
                        this._center_y = height / 2;
                        this._width = width;
                        this._height = height;

                        DOM.setXY(_clone_el, DOM.getXY(el));
                        this._left_px = _clone_el.offsetLeft;
                        this._top_px = _clone_el.offsetTop;

                        _clone_el.style.visibility = "visible";
                        _clone_el.style.filter = el.style.filter;

                        var z_index = YAHOO.util.Dom.getStyle(el, "z-index");
                        if (z_index === "auto") {
                            z_index = 0;
                        }
                        _clone_el.style.zIndex = z_index + 1;

                        _old_visibility = el.style.visibility;
                        el.style.visibility = "hidden";

                        this.setEl(_clone_el);

                        this.setRuntimeAttribute();
                        var attrs = this.runtimeAttributes._rotation;
                        var unit = attrs.unit;
                        var degrees = (unit === "deg") ? attrs.start : attrs.start * _unit_conversions[unit].deg;
                        var from_vertical = this._from_vertical = !(degrees % 180);
                        if (!from_vertical) {

                            // This only returns the computed xy compensatory offset
                            // for the start angle. It does not "setAttribute".
                            var xy_offset = this.setAttribute(null, degrees, "deg", true);

                            // We round here because we're dealing with real pixels;
                            // otherwise, rounding errors creep in.
                            this._left_px += Math.round(xy_offset[0]);
                            this._top_px += Math.round(xy_offset[1]);
                        }

                    });
                    this.onComplete.subscribe(function() {

                        // determine if we are rotating back to zero degrees,
                        // which will allow a cleaner-looking image
                        var attrs = this.runtimeAttributes._rotation;
                        var unit = attrs.unit;
                        var degrees = (unit === "deg") ? attrs.end : attrs.end * _unit_conversions[unit].deg;
                        var to_zero = !(degrees % 360);
                        var to_vertical = !(degrees % 180);

                        // Sometimes IE will fail to render the element if you
                        // change the "filter" property before restoring "visibility".
                        // Otherwise, it normally would make sense to do this after
                        // rotating and translating the source element.
                        el.style.visibility = _old_visibility;

                        if (to_zero) {
                            el.style[ie_removeProperty]("filter");
                        } else {
                            el.style.filter = _clone_el.style.filter;
                        }

                        if (this._from_vertical && to_vertical) {
                            if (_top_style) {
                                el.style.top = _top_style;
                            } else {
                                el.style[ie_removeProperty]("top");
                            }
                            if (_left_style) {
                                el.style.left = _left_style;
                            } else {
                                el.style[ie_removeProperty]("left");
                            }
                        } else {
                            DOM.setXY(el, DOM.getXY(_clone_el));
                        }

                        _clone_el.parentNode.removeChild(_clone_el);
                    });
                } else if (_transform_attribute === "WebkitTransform") {

                    // WebKit refuses (as of October 2010) to rotate inline elements
                    this.onStart.subscribe(function() {
                        var el = this.getEl();
                        var original_display = YAHOO.util.Dom.getStyle(el, "display");
                        if (original_display === "inline") {
                            el.style.display = "inline-block";
                        }
                    });
                }
            }
        };

        Rotation.NAME = "Rotation";

        YAHOO.extend(Rotation, YAHOO.util.Anim, {

            setAttribute: _transform_attribute ? function(attr, val, unit) {
                this.getEl().style[_transform_attribute] = "rotate(" + val + unit + ")";
            } : function(attr, val, unit, no_set) {
                var el, el_style, cos_val, sin_val, ie_center_x, ie_center_y, width, height;
                el = this.getEl();
                el_style = el.style;

                if (unit !== "rad") {
                    val = val * _unit_conversions[unit].rad;
                }
                val %= two_pi;
                if (val < 0) {
                    val += two_pi;
                }

                cos_val = cos(val);
                sin_val = sin(val);
                width = this._width;
                height = this._height;

                if ((val >= 0 && val < half_pi) || (val >= pi && val < pi_and_half)) {
                    ie_center_x = 0.5 * (abs(width * cos_val) + abs(height * sin_val));
                    ie_center_y = 0.5 * (abs(width * sin_val) + abs(height * cos_val));
                } else {
                    ie_center_x = 0.5 * (abs(height * sin_val) + abs(width * cos_val));
                    ie_center_y = 0.5 * (abs(height * cos_val) + abs(width * sin_val));
                }

                if (no_set) {
                    return [ie_center_x - this._center_x, ie_center_y - this._center_y];
                } else {
                    el_style.top = (this._top_px - ie_center_y + this._center_y) + "px";
                    el_style.left = (this._left_px - ie_center_x + this._center_x) + "px";
                    el_style.filter = "progid:DXImageTransform.Microsoft.Matrix(sizingMethod='auto expand'" + ",M11=" + cos_val + ",M12=" + -1 * sin_val + ",M21=" + sin_val + ",M22=" + cos_val + ")";
                }
            },

            // the only way to get this from IE would be to parse transform values,
            // which is reeeeally icky
            getAttribute: function() {
                if (!_transform_attribute) {
                    return 0;
                }

                var match = this.getEl().style[_transform_attribute].match(_rotate_regexp);
                return match ? match[1] : 0;
            },

            defaultUnit: "deg",

            setRuntimeAttribute: function() {
                var attr = "_rotation";
                var current_rotation;
                var unit = ("unit" in this.attributes) ? this.attributes[attr].unit : this.defaultUnit;
                if ("from" in this.attributes) {
                    current_rotation = this.attributes.from;
                } else {
                    current_rotation = this.getAttribute();
                    if (current_rotation) {
                        var number_units = current_rotation.match(/^(\d+)(\D+)$/);
                        if (number_units[2] === unit) {
                            current_rotation = parseFloat(number_units[1]);
                        } else {
                            current_rotation = number_units[1] * _unit_conversions[unit][number_units[2]];
                        }
                    }
                }
                this.runtimeAttributes[attr] = {
                    start: current_rotation,
                    end: this.attributes.to,
                    unit: unit
                };
                return true;
            }
        });

        CPANEL.animate.Rotation = Rotation;


        /**
         * The WindowScroll constructor.  This subclasses YAHOO.util.Scroll which itself subclasses YAHOO.util.Anim
         *   1) An element (or its ID)
         *   2) A YUI Region
         *   3) A Y-coordinate
         * @method WindowScroll
         * @param {object} obj - An object that contains the "destination" field which may be an ID, YAHOO.util.Region, or int
         */
        var WindowScroll = function() {


            var SCROLL_ANIMATION_DURATION = 0.5;
            var destination = arguments[0] || 0;
            var targetRegion;

            if (typeof destination === "string") {
                destination = DOM.get(destination);
                targetRegion = DOM.getRegion(destination);
            }

            if (typeof destination === "object") {
                if (!(destination instanceof YAHOO.util.Region)) {
                    destination = DOM.getRegion(destination);
                }
            } else {
                destination = new YAHOO.util.Point(0, destination);
            }
            targetRegion = destination;

            var scroll_window_to_y;
            var top_scroll_y = destination.top;

            // As of WHM 11.34+, there is a top banner that we need to account for;
            // otherwise the scroll will put things underneath that banner.
            if (CPANEL.is_whm() && CPANEL.Y.one(WHM_NAVIGATION_TOP_CONTAINER_SELECTOR)) {
                top_scroll_y -= DOM.get("breadcrumbsContainer").offsetHeight;
            }

            var scroll_y = DOM.getDocumentScrollTop();

            // If we've scrolled past where the notice is, scroll back.
            if (scroll_y > top_scroll_y) {
                scroll_window_to_y = top_scroll_y;
            } else {

                // If we've not scrolled far enough down to see the region,
                // scroll forward until the element is at the bottom of the screen,
                // OR the top of the element is at the top of the screen,
                // whichever comes first.
                var vp_region = CPANEL.dom.get_viewport_region();
                var bottom_scroll_y = Math.max(destination.bottom - vp_region.height, 0);
                if (scroll_y < bottom_scroll_y) {
                    scroll_window_to_y = Math.min(top_scroll_y, bottom_scroll_y);
                } else {

                    // This means the image is viewable so it should not scroll
                    scroll_window_to_y = vp_region.top;
                }
            }

            var scrollDesc = {
                scroll: {
                    to: [DOM.getDocumentScrollLeft(), scroll_window_to_y]
                }
            };

            // If the region is already in the viewport the time should be 0
            var scrollTime = CPANEL.dom.get_viewport_region().contains(targetRegion) ? 0 : SCROLL_ANIMATION_DURATION;

            var easing = YAHOO.util.Easing.easeBothStrong;

            // Whether we animate document.body or document.documentElement
            // is a mess, even in November 2017!! All of the following
            // browsers will only scroll with the given element:
            //
            // Chrome:  document.body
            // Safari:  document.documentElement
            // Edge:    document.body
            // Firefox: document.documentElement
            // IE11:    document.documentElement
            //
            // Since there appears to be no rhyme nor reason to the
            // above, we’ll animate both. Hopefully no new version
            // of any of the above will break on this. :-/

            (new YAHOO.util.Scroll(
                document.body,
                scrollDesc,
                scrollTime,
                easing
            )).animate();

            var args = [
                document.documentElement,
                scrollDesc,
                scrollTime,
                easing
            ];

            WindowScroll.superclass.constructor.apply(this, args);
        };

        WindowScroll.NAME = "WindowScroll";
        YAHOO.extend(WindowScroll, YAHOO.util.Scroll);

        CPANEL.animate.WindowScroll = WindowScroll;

    })();

} // end else statement

//--- end /usr/local/cpanel/base/cjt/animate.js ---

//--- start /usr/local/cpanel/base/cjt/api.js ---
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

//--- end /usr/local/cpanel/base/cjt/api.js ---

//--- start /usr/local/cpanel/base/cjt/color.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including color.js!");
} else {

    /**
    Color manipulation routines
    @module color
**/

    (function() {

        // http://easyrgb.com/index.php?X=MATH&H=19#text19
        var _hue_2_rgb = function(v1, v2, vH) {
            if (vH < 0) {
                vH += 1;
            }
            if (vH > 1) {
                vH -= 1;
            }
            if ((6 * vH) < 1) {
                return (v1 + (v2 - v1) * 6 * vH);
            }
            if ((2 * vH) < 1) {
                return (v2);
            }
            if ((3 * vH) < 2) {
                return (v1 + (v2 - v1) * ((2 / 3) - vH) * 6);
            }
            return (v1);
        };

        CPANEL.color = {

            // http://easyrgb.com/index.php?X=MATH&H=19#text19
            hsl2rgb: function(h, s, l) {
                var r, g, b, var_1, var_2;
                if (s == 0) { // HSL from 0 to 1
                    r = l * 255; // RGB results from 0 to 255
                    g = l * 255;
                    b = l * 255;
                } else {
                    if (l < 0.5) {
                        var_2 = l * (1 + s);
                    } else {
                        var_2 = (l + s) - (s * l);
                    }
                    var_1 = 2 * l - var_2;

                    r = 255 * _hue_2_rgb(var_1, var_2, h + (1 / 3));
                    g = 255 * _hue_2_rgb(var_1, var_2, h);
                    b = 255 * _hue_2_rgb(var_1, var_2, h - (1 / 3));
                }

                return [r, g, b];
            }
        };

    })();

}

//--- end /usr/local/cpanel/base/cjt/color.js ---

//--- start /usr/local/cpanel/base/cjt/dom.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
(function(window) {
    "use strict";

    /**
     * This module contains various CJT extension methods supporting
     * dom object minipulation and measurement.
     * @module  Cpanel.dom
     */

    // ----------------------
    // Shortcuts
    // ----------------------
    var YAHOO = window.YAHOO;
    var DOM = window.DOM;
    var EVENT = window.EVENT;
    var document = window.document;
    var CPANEL = window.CPANEL;

    // ----------------------
    // Setup the namespaces
    // ----------------------
    CPANEL.namespace("dom");

    var _ARROW_KEY_CODES = {
        37: 1,
        38: 1,
        39: 1,
        40: 1
    };

    /**
     * Used internally for normalizing <select> keyboard behavior.
     *
     * @method _do_blur_and_focus
     * @private
     */
    var _do_blur_then_focus = function() {
        this.blur();
        this.focus();
    };

    // Used for creating arbitrary markup.
    var dummy_div;

    YAHOO.lang.augmentObject(CPANEL.dom, {

        /**
         * Detects if the oninput event is working for the current browser.
         * NOTE: IE9's oninput event is horribly broken. Best just to avoid it.
         * http://msdn.microsoft.com/en-us/library/ie/gg592978%28v=vs.85%29.aspx
         *
         * @property has_oninput
         * @static
         * @type {Boolean}
         */
        has_oninput: (parseInt(YAHOO.env.ua.ie, 10) !== 9) && ("oninput" in document.createElement("input")),

        /**
         * Gets the region for the content box.
         * @method get_content_region
         * @static
         * @param  {String|HTMLElement} el Element to calculate the region.
         * @return {YAHOO.util.Region}    Region consumed by the element. Accounts for
         * padding and border. Also has custom properties:
         *   @param {[2]} outer_xy XY of the outer bounds?
         *   @param {RegionLike} padding Padding size for element
         *   @param {RegionLike} border Border top and left sizes.
         */
        get_content_region: function(el) {
            el = DOM.get(el);

            var padding_top = parseFloat(DOM.getStyle(el, "paddingTop")) || 0;
            var padding_bottom = parseFloat(DOM.getStyle(el, "paddingBottom")) || 0;
            var padding_left = parseFloat(DOM.getStyle(el, "paddingLeft")) || 0;
            var padding_right = parseFloat(DOM.getStyle(el, "paddingRight")) || 0;

            var border_left = parseFloat(DOM.getStyle(el, "borderLeftWidth")) || 0;
            var border_top = parseFloat(DOM.getStyle(el, "borderTopWidth")) || 0;

            var xy = DOM.getXY(el);
            var top = xy[1] + border_top + padding_top;
            var left = xy[0] + border_left + padding_left;
            var bottom = top + el.clientHeight - padding_top - padding_bottom;
            var right = left + el.clientWidth - padding_left - padding_right;

            var region = new YAHOO.util.Region(top, right, bottom, left);
            region.outer_xy = xy;
            region.padding = {
                "top": padding_top,
                right: padding_right,
                bottom: padding_bottom,
                left: padding_left
            };

            region.border = {
                "top": border_top,

                // no bottom or right since these are unneeded here
                left: border_left
            };

            return region;
        },

        /**
         * Gets the height of the element accounting for border and
         * padding offsets.
         * @method  get_content_height
         * @static
         * @param  {HTMLElement|String} el Element to measure.
         * @return {Number}    Height of the element.
         */
        get_content_height: function(el) {
            el = DOM.get(el);

            // most browsers return something useful from this
            var dom = parseFloat(DOM.getStyle(el, "height"));
            if (!isNaN(dom)) {
                return dom;
            }

            // IE makes us get it this way
            var padding_top = parseFloat(DOM.getStyle(el, "paddingTop")) || 0;
            var padding_bottom = parseFloat(DOM.getStyle(el, "paddingBottom")) || 0;

            var client_height = el.clientHeight;

            if (client_height) {
                return client_height - padding_top - padding_bottom;
            }

            var border_top = parseFloat(DOM.getStyle(el, "borderTopWidth")) || 0;
            var border_bottom = parseFloat(DOM.getStyle(el, "borderBottomWidth")) || 0;
            return el.offsetHeight - padding_top - padding_bottom - border_top - border_bottom;
        },

        /**
         * Gets the width of the element accounting for border and
         * padding offsets.
         * @method  get_content_width
         * @static
         * @param  {HTMLElement|String} el Element to measure.
         * @return {Number}    Width of the element.
         */
        get_content_width: function(el) {
            el = DOM.get(el);

            // most browsers return something useful from this
            var dom = parseFloat(DOM.getStyle(el, "width"));
            if (!isNaN(dom)) {
                return dom;
            }

            // IE makes us get it this way
            var padding_left = parseFloat(DOM.getStyle(el, "paddingLeft")) || 0;
            var padding_right = parseFloat(DOM.getStyle(el, "paddingRight")) || 0;

            var client_width = el.clientWidth;

            if (client_width) {
                return client_width - padding_left - padding_right;
            }

            var border_left = parseFloat(DOM.getStyle(el, "borderLeftWidth")) || 0;
            var border_right = parseFloat(DOM.getStyle(el, "borderRightWidth")) || 0;
            return el.offsetWidth - padding_left - padding_right - border_left - border_right;
        },

        /**
         * Gets the region of the current viewport
         * @method  get_viewport_region.
         * @return {YAHOO.util.Region} region for the viewport
         */
        get_viewport_region: function() {
            var vp_width = DOM.getViewportWidth();
            var vp_height = DOM.getViewportHeight();

            var scroll_x = DOM.getDocumentScrollLeft();
            var scroll_y = DOM.getDocumentScrollTop();
            return new YAHOO.util.Region(
                scroll_y,
                scroll_x + vp_width,
                scroll_y + vp_height,
                scroll_x
            );
        },

        /**
         * Adds the class if it does not exist, removes it if it does
         * exist on the element.
         * @method toggle_class
         * @static
         * @param  {HTMLElement|String} el The element to toggle the
         * CSS class name.
         * @param  {String} the_class A CSS class name to add or remove.
         */
        toggle_class: function(el, the_class) {
            el = DOM.get(el);

            // TODO: May want to consider caching since these are expensive to
            // regenerate on each call.
            var pattern = new RegExp("\\b" + the_class.regexp_encode() + "\\b");
            if (el.className.search(pattern) === -1) {
                DOM.addClass(el, the_class);
                return the_class;
            } else {
                DOM.removeClass(el, the_class);
            }
        },

        /**
         * Create one or more DOM nodes from markup.
         * These nodes are NOT injected into the page.
         *
         * @method create_from_markup
         * @param markup {String} HTML to use for creating DOM nodes
         * @return {Array} The DOM element nodes from the markup.
         */
        create_from_markup: function(markup) {
            if (!dummy_div) {
                dummy_div = document.createElement("div");
            }
            dummy_div.innerHTML = markup;

            return CPANEL.Y(dummy_div).all("> *");
        },

        /**
         * Ensure that keyboard manipulation of the <select> box will change
         * the actual value right away. On some platforms (e.g., MacOS),
         * "onchange" doesn't fire on up/down arrows until you blur() the element.
         *
         * This is primarily useful for validation; we might not want to use this
         * if "onchange" fires off anything "big" in the UI since it breaks users'
         * expectations of how drop-downs behave on their platform.
         *
         * On a related note, bear in mind that document.activeElement will be
         * different when "onchange" fires from a blur(): if it fires natively from
         * an arrow keydown, then activeElement is the <select>;
         * after a blur(), document.activeElement is probably document.body.
         *
         * @method normalize_select_arrows
         * @static
         */
        normalize_select_arrows: function(el) {
            EVENT.on(el, "keydown", function(e) {
                if (e.keyCode in _ARROW_KEY_CODES) {
                    window.setTimeout(_do_blur_then_focus.bind(this), 1);
                }
            });
        },

        /**
         * Sets the value of the element to the passed in value. If form is
         * provided, will be in the specified form.
         * @method  set_form_el_value
         * @static
         * @param {HTMLElement|String} form Optional, either a DOM element or
         * an ID of the form.
         * @param {HTMLCollection, HTMLSelect, HTMLInput, HTMLTextarea, String} el  can be an
         * HTML collection, a <select> element, an <input>, a <textarea>,
         * a name in the form, or an ID of one of these.
         * @param {Any} val  Value to set the element to.
         * @return {Boolean} true if successful, false otherwise.
         */
        set_form_el_value: function(form, el, val) {
            if (arguments.length === 2) {
                val = el;
                el = form;
                form = null;
            }

            // TODO: Need to check if form is found before calling form[el],
            // will throw an uncaught exception.
            if (typeof el === "string") {
                var element = null;
                if (form) {
                    form = DOM.get(form);
                    if (form) {

                        // Assumes the el is a name before
                        // checking if its an id further down.
                        element = form[el];
                    }
                }

                if (!element) {

                    // Form was not provided,
                    // el is an id and not a named form item,
                    // or el is already a DOM node.
                    element = DOM.get(el);
                }

                el = element;
            }

            var opts = el.options;
            if (opts) {
                for (var o = opts.length - 1; o >= 0; o--) {
                    if (opts[o].value === val) {
                        el.selectedIndex = o; // If a multi-<select>, clobber.
                        return true;
                    }
                }
            } else if ("length" in el) {
                for (var e = el.length - 1; e >= 0; e--) {
                    if (el[e].value === val) {
                        el[e].checked = true;
                        return true;
                    }
                }
            } else if ("value" in el) {
                el.value = val;
                return true;
            }

            return false;
        },

        /**
         * Shows the current element.
         * @method show
         * @static
         * @param {String|HTMLElement} el element to show
         * @param {String} display_type optional, alternative display type if the default is not desired */
        show: function(el, display_type) {
            display_type = display_type || "";
            DOM.setStyle(el, "display", display_type);
        },

        /**
         * Hides the current element.
         * @method hide
         * @static
         * @param {String|HTMLElement} el element to hide */
        hide: function(el) {
            DOM.setStyle(el, "display", "none");
        },

        /**
         * Checks if the current element is visible.
         * @method isVisible
         * @static
         * @param {String|HTMLElement} el element to check
         * @return {Boolean} true if visible, false if not. */
        isVisible: function(el) {
            return DOM.getStyle(el, "display") !== "none";
        },

        /**
         * Checks if the current element is hidden.
         * @method isHidden
         * isHidden
         * @param {String|HTMLElement} el element to check
         * @return {Boolean} true if not visible, false otherwise. */
        isHidden: function(el) {
            return DOM.getStyle(el, "display") === "none";
        },

        /**
         * Determins if the passed in element or
         * the documentElement if no element is passed in,
         * is in RTL mode.
         * @method isRtl
         * @param  {String|HtmlElement}  el Optional element, if provided,
         * this function will look for the dir attribute on the element, otherwise
         * it will look at the document.documentElement dir attribute.
         * @return {Boolean}    The document or element is in rtl if true and in ltr
         * if false.
         */
        isRtl: function(el) {
            if (!el) {
                if (document) {
                    return (document.documentElement.dir === "rtl");
                }
            } else {
                el = DOM.get(el);
                if (el) {
                    return el.dir === "rtl";
                }
            }

            // We are not operating in a browser
            // so we don't know, so just say no.
            return false;
        }
    });

    // QUESTION: Why do we need the same function with different names?
    CPANEL.dom.get_inner_region = CPANEL.dom.get_content_region;

})(window);

//--- end /usr/local/cpanel/base/cjt/dom.js ---

//--- start /usr/local/cpanel/base/cjt/dragdrop.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 *
 * A module with various drag-and-drop implementations.
 * @module CPANEL.dragdrop
 *
 */

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including dragdrop.js!");
} else {

    // keep things out of global scope
    (function() {

        // cache variable lookups
        var DDM = YAHOO.util.DragDropMgr;
        var ddtarget_prototype = YAHOO.util.DDTarget.prototype;
        var get = DOM.get;
        var get_next_sibling = DOM.getNextSibling;
        var get_xy = DOM.getXY;
        var set_xy = DOM.setXY;
        var get_style = DOM.getStyle;
        var get_content_height = CPANEL.dom.get_content_height;
        var ease_out = YAHOO.util.Easing.easeOut;

        /**
         *
         * This class extends DDProxy with several event handlers and
         * a custom createFrame method. If you extend event handlers beyond this class,
         * be sure to call DDItem's handlers, e.g.:
         * DDItem.prototype.<event name>.apply(this, arguments);
         * @class DDItem
         * @namespace CPANEL.dragdrop
         * @extends YAHOO.util.DDProxy
         * @constructor
         * @param {String|HTMLElement} id See parent class documentation.
         * @param {String} sGroup See parent class documentation.
         * @param {config} Passed to parent class constructor, and also accepts:
         *                 drag_region: of type YAHOO.util.Region
         *                 placeholder: an HTML Element or ID to designate as the item's placeholder
         *                 animation: whether to animate DDItem interactions (default: true)
         *                 animation_proxy_class: class for a DDItem animation proxy (default: _cp_animation_proxy)
         *
         */
        var DDItem = function(id, sGroup, config) {
            DDItem.superclass.constructor.apply(this, arguments);

            if (!config) {
                return;
            }

            if ("drag_region" in config) {
                var region = config.drag_region;

                var el = this.getEl();
                var xy = get_xy(el);

                if (region.width) {
                    var width = el.offsetWidth;
                    var el_left = xy[0];
                    var left = el_left - region.left;
                    var right = region.right - el_left - width;
                    this.setXConstraint(left, right);
                }

                if (region.height) {
                    var height = el.offsetHeight;
                    var el_top = xy[1];
                    var top = el_top - region.top;
                    var bottom = region.bottom - el_top - height;
                    this.setYConstraint(top, bottom);
                }
            }

            if ("placeholder" in config) {
                var new_placeholder = get(config.placeholder);
                if (!new_placeholder && typeof config.placeholder === "string") {
                    new_placeholder = document.createElement("div");
                    new_placeholder.id = config.placeholder;
                }

                var _placeholder_style = new_placeholder.style;

                this._placeholder = new_placeholder;
                this._placeholder_style = _placeholder_style;

                _placeholder_style.position = "absolute";
                _placeholder_style.visibility = "hidden";
                document.body.appendChild(new_placeholder);

                // put this in the prototype so it's done once then available to all class members
                this.constructor.prototype._placeholder_hidden = true;
            }

            if ("animation" in config) {
                this._animation = config.animation;
            }
            if (this._animation) {
                if ("animation_proxy_class" in config) {
                    this._animation_proxy_class = config.animation_proxy_class;
                }
            }
        };

        YAHOO.extend(DDItem, YAHOO.util.DDProxy, {

            // initial values
            _going_up: null,
            _last_y: null,

            // defaults
            _animation: true,
            _animation_proxy_class: "_cp_animation_proxy",

            _sync_placeholder: function() {
                var placeholder = this._placeholder;
                var srcEl = this.getEl();
                if (!this._placeholder_hidden && this._animation) {
                    var motion = new YAHOO.util.Motion(
                        placeholder, {
                            points: {
                                to: get_xy(srcEl)
                            }
                        },
                        0.2
                    );
                    motion.animate();
                } else {
                    set_xy(placeholder, get_xy(srcEl));
                    this._placeholder_initialized = true;
                }
                if (this._placeholder_hidden) {
                    var _style = this._placeholder_style;
                    copy_size(srcEl, placeholder, _style);
                    _style.visibility = "";
                    this._placeholder_hidden = false;
                }
            },

            // override the default styles in DDProxy to create just a basic div
            createFrame: function() {
                var proxy = this.getDragEl();
                if (!proxy) {
                    proxy = document.createElement("div");
                    proxy.id = this.dragElId;
                    proxy.style.position = "absolute";
                    proxy.style.zIndex = "999";
                    document.body.insertBefore(proxy, document.body.firstChild);
                }
            },

            startDrag: function(x, y) {

                // make the proxy look like the source element
                var dragEl = this.getDragEl();
                var clickEl = this.getEl();

                dragEl.innerHTML = clickEl.innerHTML;
                clickEl.style.visibility = "hidden";
                if ("_placeholder" in this) {
                    this._sync_placeholder();
                }
            },

            endDrag: function(e) {
                var srcEl = this.getEl();
                var proxy = this.getDragEl();
                var proxy_style = proxy.style;

                // Show the proxy element and animate it to the src element's location
                proxy_style.visibility = "";
                var a = new YAHOO.util.Motion(
                    proxy, {
                        points: {
                            to: get_xy(srcEl)
                        }
                    },
                    0.2,
                    ease_out
                );

                var that = this;

                // Hide the proxy and show the source element when finished with the animation
                a.onComplete.subscribe(function() {
                    proxy_style.visibility = "hidden";
                    srcEl.style.visibility = "";

                    if ("_placeholder" in that) {
                        that._placeholder_style.visibility = "hidden";
                        that._placeholder_hidden = true;
                    }
                });
                a.animate();
            },

            onDrag: function(e) {

                // Keep track of the direction of the drag for use during onDragOver
                var y = EVENT.getPageY(e);
                var last_y = this._last_y;

                if (y < last_y) {
                    this._going_up = true;
                } else if (y > last_y) {
                    this._going_up = false;
                } else {
                    this._going_up = null;
                }

                this._last_y = y;
            },

            // detect a new parent element
            onDragEnter: function(e, id) {
                if (this.parent_id === null) {
                    var srcEl = this.getEl();
                    var destEl = get(id);

                    this.parent_id = id;

                    if (this.last_parent !== id) {
                        destEl.appendChild(srcEl);
                    }

                    if ("placeholder" in this) {
                        this._sync_placeholder();
                    }
                }
            },

            onDragOut: function(e, id) {
                if (this.getEl().parentNode === get(id)) {
                    this.last_parent = id;
                    this.parent_id = null;
                }
            },

            onDragOver: function(e, id) {
                var srcEl = this.getEl();
                var destEl = get(id);

                // we don't care about horizontal motion here
                var going_up = this._going_up;
                if (going_up === null) {
                    return;
                }

                // We are only concerned with draggable items, not containers
                var is_container = ddtarget_prototype.isPrototypeOf(DDM.getDDById(id));
                if (is_container) {
                    return;
                }

                var parent_el = destEl.parentNode;

                // When drag-dropping between targets, sometimes the srcEl is inserted
                // below the destEl when the mouse is going down.
                // The result is that the srcEl keeps being re-inserted and re-inserted.
                // Weed this case out.
                var next_after_dest = get_next_sibling(destEl);
                var dest_then_src = (next_after_dest === srcEl);
                if (!going_up && dest_then_src) {
                    return;
                }

                if (this._animation) {

                    // similar check to the above;
                    // this only seems to happen when there is animation
                    var src_then_dest = (get_next_sibling(srcEl) === destEl);
                    if (going_up && src_then_dest) {
                        return;
                    }

                    // only animate adjacent drags
                    if (src_then_dest || dest_then_src) {
                        dp_parent = document.body;

                        var dest_proxy = document.createElement("div");
                        dest_proxy.className = this._animation_proxy_class;
                        var dp_style = dest_proxy.style;

                        dp_style.position = "absolute";
                        dp_style.display = "none";
                        dest_proxy.innerHTML = destEl.innerHTML;
                        copy_size(destEl, dest_proxy, dp_style);
                        dp_parent.appendChild(dest_proxy);

                        var dest_proxy_motion_destination = get_xy(srcEl);
                        var height_difference = get_content_height(dest_proxy) - get_content_height(srcEl);
                        if (going_up) {
                            dest_proxy_motion_destination[1] -= height_difference;
                        }

                        var attrs = {
                            points: {
                                from: get_xy(destEl),
                                to: dest_proxy_motion_destination
                            }
                        };
                        var anim = new YAHOO.util.Motion(dest_proxy, attrs, 0.25);

                        var de_style = destEl.style;
                        anim.onComplete.subscribe(function() {
                            de_style.visibility = "";
                            dp_parent.removeChild(dest_proxy);
                        });

                        dp_style.display = "";
                        de_style.visibility = "hidden";
                        anim.animate();
                    }
                }

                if (going_up) {
                    parent_el.insertBefore(srcEl, destEl); // insert above
                } else {
                    parent_el.insertBefore(srcEl, next_after_dest); // insert below
                }

                if ("_placeholder" in this) {
                    this._sync_placeholder();
                }

                DDM.refreshCache();
            }
        });

        // pass in the style as a parameter to save a lookup
        var copy_size = function(src, dest, dest_style) {
            var br = parseFloat(get_style(dest, "border-right-width")) || 0;
            var bl = parseFloat(get_style(dest, "border-left-width")) || 0;
            var newWidth = Math.max(0, src.offsetWidth - br - bl);

            var bt = parseFloat(get_style(dest, "border-top-width")) || 0;
            var bb = parseFloat(get_style(dest, "border-bottom-width")) || 0;
            var newHeight = Math.max(0, src.offsetHeight - bt - bb);

            dest_style.width = newWidth + "px";
            dest_style.height = newHeight + "px";
        };

        CPANEL.dragdrop = {

            /**
             *
             * This method returns an object of "items" that can be drag-dropped
             * among the object's "containers".
             * @method containers
             * @namespace CPANEL.dragdrop
             * @param { Array | HTMLElement } containers Either a single HTML container (div, ul, etc.) or an array of containers to initialize as YAHOO.util.DDTarget objects and whose "children" will be initialized as CPANEL.dragdrop.DDItem objects.
             * @param { String } group The DragDrop group to use in initializing the containers and items.
             * @param { object } config Options for YAHOO.util.DDTarget and CPANEL.dragdrop.DDItem constructors; accepts:
             *                   item_constructor: function to use for creating the item objects (probably override DDItem)
             *
             */
            containers: function(containers, group, config) {
                if (!(containers instanceof Array)) {
                    containers = [containers];
                }

                var container_objects = [];
                var drag_item_objects = [];

                var item_constructor = (config && config.item_constructor) || DDItem;

                var containers_length = containers.length;
                for (var c = 0; c < containers_length; c++) {
                    var cur_container = get(containers[c]);
                    container_objects.push(new YAHOO.util.DDTarget(cur_container, group, config));

                    var cur_contents = cur_container.children;
                    var cur_contents_length = cur_contents.length;
                    for (var i = 0; i < cur_contents_length; i++) {
                        drag_item_objects.push(new item_constructor(cur_contents[i], group, config));
                    }
                }

                return {
                    containers: container_objects,
                    items: drag_item_objects
                };
            },
            DDItem: DDItem
        };

    })();

} // end else statement

//--- end /usr/local/cpanel/base/cjt/dragdrop.js ---

//--- start /usr/local/cpanel/base/cjt/fixes.js ---
(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var DOM = YAHOO.util.Dom;
    var EVENT = window.EVENT;

    var L = YAHOO.lang;

    // YUI bugs 2529100 and 2529292
    // The fix for these in YUI 2.9.0 does not work.
    if (YAHOO.lang.substitute("{a} {b}", {
        a: "1",
        b: "{"
    }) !== "1 {") {
        YAHOO.lang.substitute = function(s, o, f) {
            var i, j, k, key, v, meta, saved = [],
                token,
                DUMP = "dump",
                SPACE = " ",
                LBRACE = "{",
                RBRACE = "}",
                dump, objstr;

            for (;;) {
                i = i ? s.lastIndexOf(LBRACE, i - 1) : s.lastIndexOf(LBRACE);
                if (i < 0) {
                    break;
                }
                j = s.indexOf(RBRACE, i);

                // YUI 2 bug 2529292
                // YUI 2.8.2 uses >= here, which kills the function on "{}"
                if (i + 1 > j) {
                    break;
                }

                // Extract key and meta info
                token = s.substring(i + 1, j);
                key = token;
                meta = null;
                k = key.indexOf(SPACE);
                if (k > -1) {
                    meta = key.substring(k + 1);
                    key = key.substring(0, k);
                }

                // lookup the value
                // if a substitution function was provided, execute it
                v = f ? f(key, v, meta) : o[key];

                if (L.isObject(v)) {
                    if (L.isArray(v)) {
                        v = L.dump(v, parseInt(meta, 10));
                    } else {
                        meta = meta || "";

                        // look for the keyword 'dump', if found force obj dump
                        dump = meta.indexOf(DUMP);
                        if (dump > -1) {
                            meta = meta.substring(4);
                        }

                        objstr = v.toString();

                        // use the toString if it is not the Object toString
                        // and the 'dump' meta info was not found
                        if (objstr === OBJECT_TOSTRING || dump > -1) {
                            v = L.dump(v, parseInt(meta, 10));
                        } else {
                            v = objstr;
                        }
                    }
                } else if (!L.isString(v) && !L.isNumber(v)) {
                    continue;

                    // unnecessary with fix for YUI bug 2529100
                    //                // This {block} has no replace string. Save it for later.
                    //                v = "~-" + saved.length + "-~";
                    //                saved[saved.length] = token;
                    //
                    //                // break;
                }

                s = s.substring(0, i) + v + s.substring(j + 1);

            }

            // unnecessary with fix for YUI bug 2529100
            //        // restore saved {block}s
            //        for (i=saved.length-1; i>=0; i=i-1) {
            //            s = s.replace(new RegExp("~-" + i + "-~"), "{"  + saved[i] + "}", "g");
            //        }

            return s;
        };
    }

    if (YAHOO.widget.Panel) {
        var panel_proto = YAHOO.widget.Panel.prototype;

        // YUI 2 bug 2529256: avoid focusing unchecked radio buttons in tab loop
        // Strictly speaking, this should be fixed for focusLast as well,
        // but the usefulness of that seems questionable since the only breakage case
        // is that the last focusable element in the panel/dialog would be a radio
        // button.
        // This runs the original focusFirst() method then advances the focus to
        // the next non-enabled-unchecked-radio focusable element if necessary.
        // This is not being fixed for YUI 2.9.0.
        if (!panel_proto.focusFirst._2529256_fixed) {
            ["Panel", "Dialog"].forEach(function(module) {
                var _focus_first = YAHOO.widget[module].prototype.focusFirst;
                YAHOO.widget[module].prototype.focusFirst = function() {
                    var focused_el = _focus_first.apply(this, arguments) && document.activeElement;

                    if (focused_el && (("" + focused_el.type).toLowerCase() === "radio") && !focused_el.checked) {
                        var els = this.focusableElements;
                        var i = els && els.indexOf(focused_el);
                        if (i !== -1) {
                            i++;
                            var cur_el = els[i];
                            while (cur_el) {
                                if (!cur_el.disabled && ((("" + cur_el.type).toLowerCase() !== "radio") || cur_el.checked)) {
                                    break;
                                }
                                i++;
                                cur_el = els[i];
                            }
                            if (cur_el && cur_el.focus) {
                                cur_el.focus();
                                focused_el = cur_el;
                            }
                        }
                    }

                    return !!focused_el;
                };
                YAHOO.widget[module].prototype.focusFirst._2529256_fixed = true;
            });
        }

        // YUI 2 bug 2529257: prevent back-TAB from escaping focus out of a modal Panel
        // This is not being fixed for YUI 2.9.0.
        var _set_first_last_focusable = panel_proto.setFirstLastFocusable;

        var catcher_html = "<input style='position:absolute;top:1px;outline:0;margin:0;border:0;padding:0;height:1px;width:1px;z-index:-1' />";
        var _catcher_div = document.createElement("div");
        _catcher_div.innerHTML = catcher_html;
        var catcher_prototype = _catcher_div.firstChild;
        DOM.setStyle(catcher_prototype, "opacity", 0);

        panel_proto.setFirstLastFocusable = function() {
            _set_first_last_focusable.apply(this, arguments);

            if (this.firstElement && !this._first_focusable_catcher) {
                var first_catcher = catcher_prototype.cloneNode(false);
                YAHOO.util.Event.on(first_catcher, "focus", function() {
                    first_catcher.blur();
                    this.focusLast();
                }, this, true);
                this.innerElement.insertBefore(first_catcher, this.innerElement.firstChild);
                this._first_focusable_catcher = first_catcher;

                var last_catcher = catcher_prototype.cloneNode(false);
                YAHOO.util.Event.on(last_catcher, "focus", function() {
                    last_catcher.blur();
                    this.focusFirst();
                }, this, true);
                this.innerElement.appendChild(last_catcher);
                this._last_focusable_catcher = last_catcher;
            }
        };

        var _get_focusable_elements = panel_proto.getFocusableElements;
        panel_proto.getFocusableElements = function() {
            var els = _get_focusable_elements.apply(this, arguments);

            // An element that has display:none is not focusable.
            var len = els.length;
            for (var i = 0; i < len; i++) {
                if (DOM.getStyle(els[i], "display") === "none") {
                    els.splice(i, 1);
                    i--;
                }
            }

            if (els.length) {
                if (this._first_focusable_catcher) {
                    els.shift();
                }
                if (this._last_focusable_catcher) {
                    els.pop();
                }
            }

            return els;
        };

        // In WebKit and Opera, Panel assumes that we can't focus() its innerElement.
        // To compensate, it creates a dummy <button> and puts it into the
        // innerElement, absolutely positioned with left:-10000em. In LTR this is
        // fine, but in RTL it makes the screen REEEALLY wide.
        //
        // To fix, just replace the "left" CSS style with "right".
        if (document.documentElement.dir === "rtl") {
            var rtl_createHidden = panel_proto._createHiddenFocusElement;
            panel_proto._createHiddenFocusElement = function() {
                if (typeof this.innerElement.focus !== "function") {
                    rtl_createHidden.apply(this, arguments);
                    this._modalFocus.style.right = this._modalFocus.style.left;
                    this._modalFocus.style.left = "";
                }
            };
        }
    }

    // Make YUI 2 AutoComplete play nicely with RTL.
    // This is a little inefficient since it will have just set _elContainer for
    // LTR in the DOM, but it's a bit cleaner than rewriting snapContainer entirely.
    if (document.documentElement.dir === "rtl") {
        EVENT.onDOMReady(function() {
            if ("AutoComplete" in YAHOO.widget) {
                var _do_before_expand = YAHOO.widget.AutoComplete.prototype.doBeforeExpandContainer;
                YAHOO.widget.AutoComplete.prototype.doBeforeExpandContainer = function() {
                    var xpos = DOM.getX(this._elTextbox);
                    var containerwidth = this._elContainer.offsetWidth;
                    if (containerwidth) {
                        xpos -= containerwidth - DOM.get(this._elTextbox).offsetWidth;
                        DOM.setX(this._elContainer, xpos);
                    }

                    return _do_before_expand.apply(this, arguments);
                };
            }
        });
    }

    /*
     * 1) Instantiate an Overlay with an "effect" on show.
     * 2) .show() the Overlay object.
     * 3) .destroy() the Overlay object before it finishes animating in.
     *
     * OBSERVE: A very confusing JS error results once that "effect"
     * finishes animating in because the .destroy() call doesn't pull the plug
     * on the animation, and the animation presumes that the DOM object is still
     * there after it's done.
     *
     * The fix relies on the "cacheEffects" property being true (which it is
     * by default). It also accesses private methods and properties, but since
     * Yahoo! no longer maintains this code, that shouldn't be a problem.
     */
    if (YAHOO.widget && YAHOO.widget.Overlay) {
        var ovl_destroy = YAHOO.widget.Overlay.prototype.destroy;
        YAHOO.widget.Overlay.prototype.destroy = function destroy() {
            var effects = this._cachedEffects;
            if (effects && effects.length) {
                for (var e = 0; e < effects.length; e++) {

                    // Passing in (true) tells it to finish up rather than
                    // just stopping dead in its tracks.
                    effects[e]._stopAnims(true);
                }
            }

            return ovl_destroy.apply(this, arguments);
        };
    }

})(window);

//--- end /usr/local/cpanel/base/cjt/fixes.js ---

//--- start /usr/local/cpanel/base/cjt/inet6.js ---
/*
# cpanel - share/libraries/cjt2/src/util/inet6.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, module: false */

/**
 *
 * @module cjt/util/inet6
 * @example var output = inet6.parse(input).toString();
 * @exports cjt/util/inet6
 */
(function(root, factory) {
    if (typeof define === "function" && define.amd) {

        /*
         * AMD; Register as an anonymous module because
         * the filename (in this case cjt/util/inet6) will
         * become the name of the module.
         */
        define([], factory);
    } else if (typeof exports === "object") {

        /*
         * Node. Does not work with strict CommonJS, but * only CommonJS-like
         * enviroments that support module.exports, like Node.
         */
        module.exports = factory();
    } else {

        /*
         * Export to cPanel browser global namespace
         */
        if (root.CPANEL) {
            root.CPANEL.inet6 = factory();
        } else {
            root.inet6 = factory();
        }
    }
}(this, function() {
    "use strict";

    var inet = {};

    // TODO: replace with $Cpanel::Regex::regex{'ipv4'}
    var ipv4Regex = /^\d{1,3}(?:\.\d{1,3}){3}$/;
    var ipv6PartRegex = /^[0-9a-f]{1,4}$/i;

    /**
     * @constructor
     * @param {string} address - String we want to represent an IPv4 address
     *                           portion of a IPv4 compatible address
     */
    inet.Address = function(address) {
        if (address === void 0 || Object.prototype.toString.call(address) !== "[object String]") {
            throw "Invalid input: Not a String";
        }

        var parts = address.split(".");

        if (parts.length > 4) {
            throw "Invalid IPv4 address: Too many components";
        }

        if (parts.length < 4) {
            throw "Invalid IPv4 address: Too few components";
        }

        for (var i = 0, len = parts.length; i < len; i++) {
            var part = parts[i];

            if (part > 255 || part < 0) {
                throw "Invalid IPv4 address: Invalid component";
            }

            this.push(part);
        }
    };

    inet.Address.prototype = [];

    inet.Address.prototype.toString = function() {
        return this.join(".");
    };

    var inet6 = {};

    /**
     * @constructor
     * @param {string} address - the string we want to convert into an IPv6 object
     */
    inet6.Address = function(address) {
        var self = this;

        /*
         * A quick convenience for adding zero padding groups to the current
         * object.
         */
        function pad(count) {
            for (var i = 0; i < count; i++) {
                self.push(0x0000);
            }
        }

        if (address === void 0 || Object.prototype.toString.call(address) !== "[object String]") {
            throw "Invalid input: Not a String";
        }

        /*
         * First, take a look through all the address components passed to the
         * constructor.
         */
        var parts    = address.split(":");
        var expected = 8;
        var minimum  = 3;
        var count    = parts.length; /* Number of logical parts in address */
        var length   = parts.length; /* Number of string parts in address */
        var padded   = false;

        var i, part, value, first, last;

        /*
         * This value will change to true if there is a trailing IPv4 address
         * embedded in the address string.
         */
        var hasv4Address = false;

        /*
         * If the address does not contain at least "::", then bail, of course.
         */
        if (length < minimum) {
            throw "Invalid IPv6 address: Too few components";
        }

        if (length > 3 && parts[0] === "" && parts[1] === "" && parts[length - 1] === "" && parts[length - 2] === "") {
            throw "Invalid IPv6 address: Too many colons";
        }

        if (parts[0] === "" && parts[1] !== "") {
            throw "Invalid IPv6 address: Missing beginning component";
        }

        if (parts[length - 1] === "" && parts[length - 2] !== "") {
            throw "Invalid IPv6 address: Missing end component";
        }

        /*
         * Get rid of the leading and trailing double-colon effects
         */
        if (parts[0] === "" && parts[1] === "") {
            parts.shift();
            length = parts.length;
            count  = parts.length;
        }
        if (parts[parts.length - 1] === "" && parts[parts.length - 2] === "") {
            parts.pop();
            length = parts.length;
            count  = parts.length;
        }

        /*
         * If we're left with one empty item, our original address was
         * ::, so just pad the whole thing out and be done.
         */
        if (length === 1 && parts[0] === "") {
            pad(8);
            return;
        }

        /*
         * This counter is used to keep track of the number of empty components
         * in the middle of a tokenized IPv6 address string.  For example:
         *
         * fe80::1::2
         *
         * Any more than one empty component in the middle of an address leads
         * to an ambiguity in determining how much zero padding to use in an
         * address.
         */
        var emptyMiddle = 0;

        /*
         * Increase the parts count by one for each IPv4 address component
         * found.
         */
        for (i = 0; i < length; i++) {
            part = parts[i].trim();

            if (ipv4Regex.test(part)) {
                count++;
            }
        }

        for (i = 0; i < length; i++) {
            part  = parts[i].trim();
            value = null;
            first = (i ===           0) ? true : false;
            last  = (i === (length - 1)) ? true : false;

            if (ipv4Regex.test(part)) {

                /*
                 * Check for an embedded IPv4 address
                 */
                if (i !== length - 1) {
                    throw "Invalid IPv6 address: Embedded IPv4 address not at end";
                }

                for (var n = 4; n < expected - count; n++) {
                    this.shift();
                }

                var inet4address = new inet.Address(part);

                this.push((inet4address[0] << 8) | inet4address[1]);

                value        = (inet4address[2] << 8) | inet4address[3];
                hasv4Address = true;
            } else if (ipv6PartRegex.test(part)) {

                /*
                 * Check for a valid IPv6 part
                 */
                value = parseInt(part, 16);
            } else if (part === "") {
                emptyMiddle++;

                /*
                 * If we have reached an empty component, and no padding has
                 * been applied yet, then introduce the requisite amount of
                 * zero padding.
                 */
                if (!padded) {
                    pad(expected - count);
                    padded = true;
                }

                value = 0x0000;
            } else {
                throw "Invalid IPv6 address: Invalid component " + part;
            }

            this.push(value);
        }

        if (emptyMiddle > 1) {
            throw "Invalid IPv6 address: Too many colons";
        }

        if (this.length < expected) {
            throw "Invalid IPv6 address: Too few components";
        }

        if (this.length > expected) {
            throw "Invalid IPv6 address: Too many components";
        }

        if (hasv4Address) {
            for (i = 0; i < 5; i++) {
                if (this[i] !== 0x0000) {
                    throw "Invalid IPv4 compatible address";
                }
            }

            if (this[5] !== 0xffff) {
                throw "Invalid IPv6 compatible address";
            }
        }
    };

    inet6.Address.prototype = [];

    /**
     * Stringify an IPv6 address with an embedded IPv4 address
     * @return {string}
     */
    inet6.Address.prototype.toString_v4Compat = function() {
        var parts = [];

        parts.push((this[6] & 0xff00) >> 8);
        parts.push( this[6] & 0x00ff);
        parts.push((this[7] & 0xff00) >> 8);
        parts.push( this[7] & 0x00ff);

        return "::ffff:" + parts.join(".");
    };

    /**
     * Returns true if the current address object is an IPv4 compatibility
     * address; in other words, an address in the ::ffff:0:0/96 space.
     *
     * @return {boolean}
     */
    inet6.Address.prototype.isv4Compat = function() {

        /*
         * Ensure the first five uint16s of the address are 0x0000 values.
         */
        for (var i = 0; i < 5; i++) {
            if (this[i] !== 0x0000) {
                return 0;
            }
        }

        /*
         * At this point, the sixth uint16 determines if we do indeed have an
         * IPv4 compatibility address.
         */
        return (this[5] === 0xffff) ? true : false;
    };

    /**
     * Stringify an IPv6 address
     * @return {string}
     */
    inet6.Address.prototype.toString = function() {
        var ranges  = [];
        var count   = this.length;
        var last    = null;
        var longest = null;
        var range   = null;

        /*
         * If this is an IPv4 compatible address, stringify using a method that
         * will encode it in the proper quad octet notation.
         */
        if (this.isv4Compat()) {
            return this.toString_v4Compat();
        }

        /*
         * First, collate contiguous groups of zeroes into an array of
         * ranges, indicating the index within the current address object
         * of their first and their last occurences.  Along the way,
         * determine which range of contiguous zeroes is the longest,
         * preferring the rightmost one if there are multiple groups of
         * zeroes in the address.
         */
        for (var i = 0; i < count; i++) {
            var value = this[i];

            if (value !== 0x0000 || (value === 0x0000 && last !== 0x0000)) {
                ranges.push({
                    "value": value,
                    "first": i,
                    "last": i,
                    "longest": false
                });
            }

            range = ranges[ranges.length - 1];

            range.last = i;

            if (longest === null) {
                longest = range;
            }

            var currentSize =   range.last -   range.first;
            var longestSize = longest.last - longest.first;

            if (value === 0x0000 && currentSize > longestSize) {
                longest = range;
            }

            last = value;
        }

        /*
         * Next, format the number ranges into an array of string tokens,
         * adding empty tokens along the way where necessary to express
         * contiguous ranges of zeroes as accurately as possible.
         */
        var ret = [];
        var len = ranges.length;

        for (i = 0; i < len; i++) {
            range = ranges[i];

            if (range.value === 0x0000 && range === longest) {

                /*
                 * If this is the first range of contiguous zeroes in the
                 * address, then add an empty token to the left of the
                 * address to be returned.
                 */
                if (i === 0) {
                    ret.push("");
                }

                /*
                 * Regardless of the position of the longest range of
                 * contiguous zeroes, add an empty token to the output.
                 */
                ret.push("");

                /*
                 * If this is the last range of contiguous zeroes in the
                 * address, then add another empty token to the output.
                 */
                if (i === len - 1) {
                    ret.push("");
                }
            } else {
                for (var n = range.first; n <= range.last; n++) {
                    ret.push(range.value.toString(16));
                }
            }
        }

        return ret.join(":");
    };

    /**
     * Exported method to validate an IPv6 address
     * @param {string} address - IPv6 address string
     * @return {boolean}
     */
    inet6.isValid = function(address) {
        try {
            this.parse(address);
            return true;
        } catch (e) {
            return false;
        }
    };

    /**
     * Exported method for parsing IPv6 addresses to inet6.Address objects
     * @param  {string} address - IPv6 address string
     * @return {inet6.Address}
     */
    inet6.parse = function(address) {
        if (address === void 0 || Object.prototype.toString.call(address) !== "[object String]") {
            throw "Invalid input: Not a String";
        }

        return new this.Address(address);
    };

    /**
     * Reformat an IPv6 address into its canonical compact representation for
     * display; if the input is an invalid IPv6 address, it is returned to the
     * caller unmodified, otherwise the newly-reformatted address is returned
     * upon success
     *
     * @param {string} address - IPv6 address string
     * @return {string}
     */
    inet6.formatForDisplay = function(address) {
        var ret;

        try {
            var inet6 = new this.Address(address);

            ret = inet6.toString();
        } catch (e) {
            ret = address;
        }

        return ret;
    };

    return inet6;
}));

//--- end /usr/local/cpanel/base/cjt/inet6.js ---

//--- start /usr/local/cpanel/base/cjt/keyboard.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL == "undefined" || !CPANEL) {
        alert("You must include the CPANEL global object before including keyboard.js!");
    } else {
        var _is_old_ie = YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9);

        /**
        This only works with keypress listeners since it works on character codes,
        not key codes. Key codes pertain to the *key* pressed, while character
        codes pertain to the character that that key press produces.

        Browsers confuse the two in the keyCode and charCode properties.

        These methods are not foolproof; particular problems:
            * The "alpha" logic only applies to English/US-ASCII.
              Other languages' keyboards will not work correctly,
              and non-Latin alphabets will be completely broken.
            * Mouse pasting will circumvent these methods.
            * Some methods break keyboard pasting in some browsers (e.g., FF 13).

        In light of the above, use this code with caution.

        @module keyboard
    */

        /**
        The urls class URLs for AJAX calls.
        @class keyboard
        @namespace CPANEL
        @extends CPANEL
    */
        CPANEL.keyboard = {
            NUMERIC: /[0-9]/,
            LOWER_CASE_ALPHA: /[a-z]/,
            UPPER_CASE_ALPHA: /[A-Z]/,
            ALPHA: /[a-zA-Z]/,
            ALPHA_NUMERIC: /[a-zA-Z0-9]/,

            /**
            Processes the keyboard input to ignore keys outside the range.
            @name _onKeyPressAcceptValues
            @private
            @param [EventObject] e - event object passed by the framework.
            @param [RegEX] charReg - single character matching expression
        */
            _onKeyPressAcceptValues: function(e, charReg) {
                if (!charReg) {
                    return true;
                }

                // We need to reject keypress events that come from arrow keys etc.
                // We detect this in Firefox and Opera by checking for !charCode;
                // no other browser seems to fire keypress in those instances.
                //
                // We also need to ignore IE <8 since it only reports keyCode
                // for keypress in any circumstance, though it never fires keypress
                // on arrow keys.
                if (!_is_old_ie && !e.charCode) {
                    return true;
                }

                var charCode = EVENT.getCharCode(e);

                // Test to see if this character key is allowed
                var keyChar = String.fromCharCode(charCode);
                return charReg.test(keyChar);
            },

            /**
            Tests if a keypress was the return key
            @name isReturnKey
            @param [EventObject] e - event object passed by the framework.
        */
            isReturnKey: function(e) {
                return EVENT.getCharCode(e) == 13;
            },

            /**
            Allows only numeric keys to be processed.
            NOTE: This BREAKS copy/pasting with the keyboard in Firefox 13.
            @name allowNumericKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowNumericKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.NUMERIC);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only lower-case alpha (ASCII-English) keys to be processed.
            @name allowLowerCaseAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowLowerCaseAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.LOWER_CASE_ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only upper-case alpha (ASCII-English) keys to be processed.
            NOTE: This BREAKS copy/pasting with the keyboard in Firefox 13.
            @name allowUpperCaseAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowUpperCaseAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.UPPER_CASE_ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only alpha (ASCII-English) keys to be processed.
            @name allowAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only alpha (ASCII-English) and numeric keys to be processed.
            @name allowAlphaNumericKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowAlphaNumericKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.ALPHA_NUMERIC);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only keys that match the single character matching rule to be processed.
            Matching rules should only contain match patterns for single unicode characters.
            @name allowAlphaNumericKey
            @param [EventObject] e - event object passed by the framework.
            @parem [Regex] charReg - pattern matching rules for any single character.
        */
            allowPatternKey: function(e, charReg) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, charReg);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            }
        };
    }

}());

//--- end /usr/local/cpanel/base/cjt/keyboard.js ---

//--- start /usr/local/cpanel/base/cjt/legacy.json.js ---
// Use of this file is depricated as of 11.28.   This file maintained only for
// legacy cloned themes.


// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including json.js!");
} else if (typeof YAHOO.lang.JSON == "undefined" || !YAHOO.lang.JSON) {
    alert("You must include the YUI JSON library before including json.js!");
} else {

    /**
	The json module contains properties that reference json for our product.
	@module json
*/

    /**
	The json class contains properties that reference json for our product.
	@class json
	@namespace CPANEL
	@extends CPANEL
*/
    var NativeJson = Object.prototype.toString.call(this.JSON) === "[object JSON]" && this.JSON;

    CPANEL.json = {

        // Native or YUI JSON Parser
        fastJsonParse: function(s, reviver) {
            return NativeJson ?
                NativeJson.parse(s, reviver) : YAHOO.lang.JSON.parse(s, reviver);
        }


    }; // end json object
} // end else statement

//--- end /usr/local/cpanel/base/cjt/legacy.json.js ---

//--- start /usr/local/cpanel/base/cjt/nvdata.js ---
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

//--- end /usr/local/cpanel/base/cjt/nvdata.js ---

//--- start /usr/local/cpanel/base/cjt/panels.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including panels.js!");
} else {

    /**
    The panels module contains methods for creating and controlling help and modal panels.
    @module panels
*/

    /**
    The panels class contains methods for creating and controlling help and modal panels.
    @class panels
    @namespace CPANEL
    @extends CPANEL
*/
    CPANEL.panels = {

        /**
        An object of all the help panels.
        @property help_panels
    */
        help_panels: {},

        /**
        Initialize a help panel and add an event listener to toggle it's display.
        @method create_help
        @param {DOM element} panel_el The DOM element to toggle the display of the panel.
        @param {DOM element} help_el The DOM element containing the help text.
    */
        create_help: function(panel_el, help_el) {

            // get the elements
            panel_el = YAHOO.util.Dom.get(panel_el);
            help_el = YAHOO.util.Dom.get(help_el);

            // destroy the panel if it already exists (ie: if we call create_help twice on the same page)
            if (this.help_panels[panel_el.id]) {
                this.help_panels[panel_el.id].destroy();
            }

            // create the panel
            var panel_id = panel_el.id + "_yuipanel";
            var panel_options = {
                width: "300px",
                visible: false,
                draggable: false,
                close: false,
                context: [panel_el.id, "tl", "br", ["beforeShow", "windowResize", CPANEL.align_panels_event]],
                effect: {
                    effect: YAHOO.widget.ContainerEffect.FADE,
                    duration: 0.25
                }
            };
            this.help_panels[panel_el.id] = new YAHOO.widget.Panel(panel_id, panel_options);

            // body
            this.help_panels[panel_el.id].setBody(help_el.innerHTML);

            // footer
            var close_div_id = panel_el.id + "_yuipanel_close_div";
            var close_link_id = panel_el.id + "_yuipanel_close_link";
            var footer = '<div style="text-align: right">';
            footer += '<a id="' + close_link_id + '" href="javascript:void(0);">' + LOCALE.maketext("Close") + "</a>";
            footer += "</div>";
            this.help_panels[panel_el.id].setFooter(footer);

            // render the panel
            this.help_panels[panel_el.id].render(document.body);

            // put the focus on the close link after the panel is shown
            this.help_panels[panel_el.id].showEvent.subscribe(function() {
                YAHOO.util.Dom.get(close_link_id).focus();
            });

            // add the "help_panel" style class to the panel
            YAHOO.util.Dom.addClass(panel_id, "help_panel");

            // add the event handlers to close the panel
            YAHOO.util.Event.on(close_link_id, "click", function() {
                CPANEL.panels.toggle_help(panel_el.id);
            });

            // add the event handler to the toggle element
            YAHOO.util.Event.on(panel_el.id, "click", function() {
                CPANEL.panels.toggle_help(panel_el.id);
            });
        },

        /**
        Toggle a single help panel.
        @method toggle_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        toggle_help: function(el) {
            if (this.help_panels[el].cfg.getProperty("visible") === true) {
                this.help_panels[el].hide();
            } else {
                this.hide_all_help();
                this.help_panels[el].show();
            }
        },

        /**
        Show a single help panel.
        @method show_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        show_help: function(el) {
            this.help_panels[el].show();
        },

        /**
        Hide a single help panel.
        @method hide_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        hide_help: function(el) {
            this.help_panels[el].hide();
        },

        /**
        Hides all help panels.
        @method hide_all_help
    */
        hide_all_help: function() {
            for (var i in this.help_panels) {
                this.help_panels[i].hide();
            }
        }

    }; // end panels object
} // end else statement

//--- end /usr/local/cpanel/base/cjt/panels.js ---

//--- start /usr/local/cpanel/base/cjt/password.js ---
/* jshint -W108 */
// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including password.js!");
} else {
    if (!window.LOCALE) {
        window.LOCALE = new CPANEL.Locale();
    }

    /**
        The password module contains methods used for random password generation, strength validation, etc
        @module password
*/

    /**
        The password class contains methods used for random password generation, strength validation, etc
        @class password
        @namespace CPANEL
        @extends CPANEL
*/
    CPANEL.password = {

        // this function
        setup: function(password1_el, password2_el, strength_bar_el, password_strength, create_strong_el, why_strong_link_el, why_strong_text_el, min_length) {

            // check that we have received enough arguments
            if (YAHOO.util.Dom.inDocument(password1_el) == false) {
                alert("CPANEL.password.setup error: password1_el argument does not exist in the DOM!");
            }
            if (YAHOO.util.Dom.inDocument(password2_el) == false) {
                alert("CPANEL.password.setup error: password2_el argument does not exist in the DOM!");
            }
            if (YAHOO.util.Dom.inDocument(strength_bar_el) == false) {
                alert("CPANEL.password.setup error: strength_bar_el argument does not exist in the DOM!");
            }
            if (CPANEL.validate.positive_integer(password_strength) == false && password_strength != -1) {
                alert("CPANEL.password.setup error: password strength is not a positive integer!");
            }

            // handle optional arguments and set default value
            if (typeof min_length == "undefined" || CPANEL.validate.integer(min_length) == false) {
                min_length = 5;
            }

            // create the strength bar
            var password_bar = new CPANEL.password.strength_bar(strength_bar_el);

            // function to verify password strength
            var verify_password_strength = function() {
                if (password_bar.current_strength >= password_strength) {
                    return true;
                }
                return false;
            };

            // update the strength bar when we type in the password field
            password_bar.attach(password1_el, function() {
                strength_validator.verify();
            });

            // create a validator for password strength
            var strength_validator = new CPANEL.validate.validator(LOCALE.maketext("Password Strength"));
            if (password_strength != -1) {
                strength_validator.add(password1_el, "min_length(%input%, 1)", LOCALE.maketext("Password cannot be empty."));
            }
            if (min_length > 0) {
                strength_validator.add(password1_el, "min_length(%input%," + min_length + ")", LOCALE.maketext("Passwords must be at least [quant,_1,character,characters] long.", min_length));
            }
            if (password_strength > 0) {
                strength_validator.add(password1_el, verify_password_strength, LOCALE.maketext("Password strength must be at least [numf,_1].", password_strength));
            }
            strength_validator.attach();

            // create a validator for the two passwords matching
            var matching_validator = new CPANEL.validate.validator(LOCALE.maketext("Passwords Match"));
            matching_validator.add(password2_el, "equals('" + password1_el + "', '" + password2_el + "')", LOCALE.maketext("Passwords do not match."));
            matching_validator.attach();

            // create strong password link
            if (YAHOO.util.Dom.inDocument(create_strong_el) == true) {

                // function that executes when a user clicks the "use" button on the strong password dialog
                var fill_in_strong_password = function(strong_pass) {

                    // fill in the two fields
                    YAHOO.util.Dom.get(password1_el).value = strong_pass;
                    YAHOO.util.Dom.get(password2_el).value = strong_pass;

                    // verify the matching validator
                    matching_validator.verify();

                    // update the strength bar
                    password_bar.check_strength(password1_el, function() {

                        // verify the password strength
                        strength_validator.verify();
                    });
                };

                // add an event handler for the "create strong password" link
                YAHOO.util.Event.on(create_strong_el, "click", function() {
                    CPANEL.password.generate_password(fill_in_strong_password);
                });
            }

            // add an event handler for the "why?" link
            if (YAHOO.util.Dom.inDocument(why_strong_link_el) == true && YAHOO.util.Dom.inDocument(why_strong_text_el) == true) {
                CPANEL.panels.create_help(why_strong_link_el, why_strong_text_el);
            }

            // return the two validator objects we created
            return [strength_validator, matching_validator];
        },

        strength_bar: function(el) {

            // save each request so that we can cancel the last one when we fire off a new one
            this.ajax_request;

            // get the password bar element
            if (YAHOO.util.Dom.inDocument(el) == false) {
                alert("Failed to initialize password strength bar." + "\n" + "Could not find " + el + " in the DOM.");
            }
            this.strength_bar_el = YAHOO.util.Dom.get(el);

            // initialize the password strength at 0
            this.current_strength = 0;
            CPANEL.password.show_strength_bar(this.strength_bar_el, 0);

            // attach the password bar to an input field
            this.attach = function(input_el, callback_function) {

                if (YAHOO.util.Dom.inDocument(input_el) == false) {
                    alert("Failed to attach strength bar object.\n Could not find " + input_el + "in the DOM.");
                } else {

                    // if no callback function was added create one that does nothing
                    if (typeof (callback_function) === "undefined") {
                        callback_function = function() {};
                    }

                    var callback_args = {
                        "input_el": input_el,
                        "func": callback_function
                    };

                    // add event handlers to the input field
                    if (CPANEL.dom.has_oninput) {
                        EVENT.on(input_el, "input", oninput_listener, callback_args);
                    } else {
                        EVENT.on(input_el, "keyup", oninput_listener, callback_args);
                        EVENT.on(input_el, "change", oninput_listener, callback_args);

                        // The delay seems to be necessary.
                        EVENT.on(input_el, "paste", function() {
                            var that = this,
                                args = arguments;
                            setTimeout(function() {
                                oninput_listener.apply(that, args);
                            }, 5);
                        }, callback_args);
                    }
                }
            };

            // reset the bar
            this.destroy = function() {
                this.strength_bar_el.innerHTML = "";
                this.current_strength = 0;
            };

            // public wrapper for the check strength function
            this.check_strength = function(input_el, callback_function) {
                _check_strength(null, {
                    "input_el": input_el,
                    "func": callback_function
                });
            };

            // PRIVATE METHODS
            var that = this;

            var pw_strength_timeout;
            var oninput_listener = function(e, o) {
                clearTimeout(pw_strength_timeout);

                // if a request is currently active cancel it
                if (YAHOO.util.Connect.isCallInProgress(that.ajax_request)) {
                    YAHOO.util.Connect.abort(that.ajax_request);
                }

                var password = DOM.get(o.input_el).value;

                if (password in cached_strengths) {
                    that.current_strength = cached_strengths[password];
                    _update_strength_bar(cached_strengths[password]);
                    o.func();
                } else {
                    pw_strength_timeout = setTimeout(function() {
                        _check_strength(e, o);
                    }, CPANEL.password.keyup_delay_ms);
                }
            };

            var cached_strengths = {
                "": 0
            };

            // check the strength of the password
            var _check_strength = function(e, o) {


                // show a loading indicator
                _update_strength_bar(null);

                // set the value
                var password = YAHOO.util.Dom.get(o.input_el).value;

                // create the callback functions
                var callback = {
                    success: function(o2) {

                        // the responseText should be JSON data
                        try {
                            var response = YAHOO.lang.JSON.parse(o2.responseText);
                        } catch (e) {

                            // TODO: write CPANEL.errors.json();
                            alert("JSON Parse Error: Please refresh the page and try again.");
                            return;
                        }

                        // make sure strength is an integer between 0 and 100
                        var strength = parseInt(response.strength);

                        if (strength < 0) {
                            strength = 0;
                        } else if (strength > 100) {
                            strength = 100;
                        }

                        cached_strengths[password] = strength;

                        that.current_strength = strength;

                        _update_strength_bar(strength);

                        // run the callback function
                        o.func();
                    },

                    failure: function(o2) {
                        var error = '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px"><tr>';
                        error += '<td style="padding: 0px; margin: 0px; text-align: center" valign="middle">AJAX Error: Try Again</td>';
                        error += "</tr></table>";
                        YAHOO.util.Dom.get(that.strength_bar_el).innerHTML = error;
                    }
                };

                // if a request is currently active cancel it
                if (YAHOO.util.Connect.isCallInProgress(that.ajax_request)) {
                    YAHOO.util.Connect.abort(that.ajax_request);
                }

                // send the AJAX request
                var url = CPANEL.urls.password_strength();
                that.ajax_request = YAHOO.util.Connect.asyncRequest("POST", url, callback, "password=" + encodeURIComponent(password));
            };

            var _update_strength_bar = function(strength) {
                CPANEL.password.show_strength_bar(that.strength_bar_el, strength);
            };
        },

        /**
                Shows a password strength bar for a given strength.
                @method show_strength_bar
                @param {DOM element} el The DOM element to put the bar.  Should probably be a div.
                @param {integer, null} strength The strength of the bar, or null for "updating".
        */
        show_strength_bar: function(el, strength) {

            el = YAHOO.util.Dom.get(el);

            // NOTE: it would probably be more appropriate to move these colors into a CSS file, but I want the CJT to be self-contained.  this solution is fine for now
            var phrase, color;
            if (strength === null) {
                phrase = LOCALE.maketext("Loading …");
            } else if (strength >= 80) {
                phrase = LOCALE.maketext("Very Strong");
                color = "#8FFF00"; // lt green
            } else if (strength >= 60) {
                phrase = LOCALE.maketext("Strong");
                color = "#C5FF00"; // chartreuse
            } else if (strength >= 40) {
                phrase = LOCALE.maketext("OK");
                color = "#F1FF4D"; // yellow
            } else if (strength >= 20) {
                phrase = LOCALE.maketext("Weak");
                color = "#FF9837"; // orange
            } else if (strength >= 0) {
                phrase = LOCALE.maketext("Very Weak");
                color = "#FF0000"; // red
            }

            var html;

            // container div with relative positioning, height/width set to 100% to fit the container element
            html = '<div style="position: relative; width: 100%; height: 100%">';

            // phrase div fits the width and height of the container div and has its text vertically and horizontally centered; has a z-index of 1 to put it above the color bar div
            html += '<div style="position: absolute; left: 0px; width: 100%; height: 100%; text-align: center; z-index: 1; padding: 0px; margin: 0px' + (strength === null ? "; font-style:italic; color:graytext" : "") + '">';
            html += '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px"><tr style="padding: 0px; margin: 0px"><td valign="middle" style="padding: 0px; margin: 0px">' + phrase + (strength !== null ? (" (" + strength + "/100)") : "") + "</td></tr></table>"; // use a table to vertically center for greatest compatibility
            html += "</div>";

            if (strength !== null) {

                // color bar div fits the width and height of the container div and width changes depending on the strength of the password
                html += '<div style="position: absolute; left: 0px; width: ' + strength + "%; height: 100%; background-color: " + color + ';"></div>';
            }

            // close the container div
            html += "</div>";

            el.innerHTML = html;
        },

        // Time in ms between last keyup and sending off the password strength CGI
        // AJAX call. Useful to prevent an excess of aborted CGI calls.
        keyup_delay_ms: 500,


        /**
                Creates a strong password
                @method create_password
                @param {object} options (optional) options to specify limitations on the password
                @return {string} a strong password
        */
        create_password: function(options) {

            // set the length
            var length;
            if (CPANEL.validate.positive_integer(options.length) === false) {
                length = 12;
            } else {
                length = options.length;
            }

            // possible password characters
            var uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            var lowercase = "abcdefghijklmnopqrstuvwxyz";
            var numbers = "0123456789";
            var symbols = "!@#$%^&*()-_=+{}[];,.?~";

            var chars = "";
            if (options.uppercase == true) {
                chars += uppercase;
            }
            if (options.lowercase == true) {
                chars += lowercase;
            }
            if (options.numbers == true) {
                chars += numbers;
            }
            if (options.symbols == true) {
                chars += symbols;
            }

            // generate the thing
            var password = "";
            for (var i = 0; i < length; i++) {
                var rnum = Math.floor(Math.random() * chars.length);
                password += chars.substring(rnum, rnum + 1);
            }

            return password;
        },

        /**
                Pops up a modal dialog box containing a strong password.
                @method generate_password
                @param {function} use_password_function A function that gets executed when the user clicks the "Use Password" button on the modal box.  The function will have the password string sent to it as its first argument.
                @param {integer} length (optional) the length of the random password to generate.  defaults to 15
                launch_el - the element you clicked on to launch the password generator (it appears relative to this element)
        */
        generate_password: function(use_password_function, length) {

            // create the password
            var default_options = {
                length: 12,
                uppercase: true,
                lowercase: true,
                numbers: true,
                symbols: true
            };
            var password = this.create_password(default_options);

            // remove the panel if it already exists
            if (YAHOO.util.Dom.inDocument("generate_password_panel") == true) {
                var remove_me = YAHOO.util.Dom.get("generate_password_panel");
                YAHOO.util.Event.purgeElement(remove_me, true);
                remove_me.parentNode.removeChild(remove_me);
            }

            // create the panel
            var panel_options = {
                width: "380px",
                fixedcenter: true,
                close: true,
                draggable: false,
                zindex: 1000,
                visible: true,
                modal: true,
                postmethod: "manual",
                hideaftersubmit: false,
                strings: {
                    "close": LOCALE.maketext("Close")
                },
                buttons: [{
                    text: LOCALE.maketext("Use Password"),
                    handler: function() {
                        this.submit();
                    }
                }, {
                    text: LOCALE.maketext("Cancel"),
                    handler: function() {
                        this.cancel();
                    }
                }],
                effect: {
                    effect: CPANEL.animate.ContainerEffect.FADE_MODAL,
                    duration: 0.25
                }
            };
            var panel = new YAHOO.widget.Dialog("generate_password_panel", panel_options);

            panel.renderEvent.subscribe(function() {
                var buttons = this.getButtons();
                YAHOO.util.Dom.addClass(buttons[0], "input-button disabled");
                YAHOO.util.Dom.addClass(buttons[1], "input-button");
            });


            // header
            var header = '<div class="header"><div class="lt"></div>';
            header += "<span>" + LOCALE.maketext("Password Generator") + "</span>";
            header += '<div class="rt"></div></div>';
            panel.setHeader(header);

            // body
            var body = '<div id="generate_password_body_div">';

            body += '<table id="generate_password_table">';
            body += "<tr>";
            body += '<td><input id="generate_password_input_field" type="text" value="' + password + '" size="27"  /></td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td><input type="button" class="input-button btn btn-primary" value="' + LOCALE.maketext("Generate Password") + '" id="generate_password_reload" /></td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td><span class="action_link" id="generate_password_toggle_advanced_options">' + LOCALE.maketext("Advanced Options") + " &raquo;</span>";

            body += '<div id="generate_password_advanced_options" style="display: none"><table style="width: 100%">';
            body += "<tr>";
            body += '<td colspan="2">' + LOCALE.maketext("Length") + ': <input type="text" id="generate_password_length" size="2" maxlength="2" value="12" /> (10-18)</td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td width="50%">' + LOCALE.maketext("Alpha Characters") + ":</td>";
            body += '<td width="50%">' + LOCALE.maketext("Non Alpha Characters") + ":</td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_mixed_alpha" checked="checked" /> <label for="generate_password_mixed_alpha">' + LOCALE.maketext("Both") + " (aBcD)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_mixed_nonalpha" checked="checked" /> <label for="generate_password_mixed_nonalpha">' + LOCALE.maketext("Both") + " (1@3$)</label></td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_lowercase" /> <label for="generate_password_lowercase">' + LOCALE.maketext("Lowercase") + " (abc)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_numbers" /> <label for="generate_password_numbers">' + LOCALE.maketext("Numbers") + " (123)</label></td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_uppercase" /> <label for="generate_password_uppercase">' + LOCALE.maketext("Uppercase") + " (ABC)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_symbols" /> <label for="generate_password_symbols">' + LOCALE.maketext("Symbols") + " (@#$)</label></td>";
            body += "</tr>";
            body += "</table></div>";

            body += "</td></tr></table>";

            body += '<p><input type="checkbox" id="generate_password_confirm" /> <label for="generate_password_confirm">' + LOCALE.maketext("I have copied this password in a safe place.") + "</label></p>";

            body += "</div>";
            panel.setBody(body);

            // render the panel
            panel.render(document.body);

            if (CPANEL.password.fade_from) {
                CPANEL.password.fade_from.fade_to(panel);
            }

            // make sure the input button is not checked (defeat browser caching)
            YAHOO.util.Dom.get("generate_password_confirm").checked = false;


            panel.validate = function() {
                return DOM.get("generate_password_confirm").checked;
            };
            panel.submitEvent.subscribe(function() {
                use_password_function(YAHOO.util.Dom.get("generate_password_input_field").value);
                this.cancel();
            });
            panel.cancelEvent.subscribe(function() {
                if (CPANEL.password.fade_from) {
                    panel.fade_to(CPANEL.password.fade_from);
                }
            });
            panel.hideEvent.subscribe(panel.destroy, panel, true);


            YAHOO.util.Event.on("generate_password_confirm", "click", function() {
                this.checked ? YAHOO.util.Dom.removeClass(panel.getButtons()[0], "disabled") : YAHOO.util.Dom.addClass(panel.getButtons()[0], "disabled");
            });

            // select the input field when the user clicks on it
            YAHOO.util.Event.on("generate_password_input_field", "click", function() {
                YAHOO.util.Dom.get("generate_password_input_field").select();
            });

            YAHOO.util.Event.on("generate_password_toggle_advanced_options", "click", function() {
                CPANEL.animate.slide_toggle("generate_password_advanced_options");
            });

            // get the password options from the interface
            var get_password_options = function() {
                var options = {};

                var length_el = YAHOO.util.Dom.get("generate_password_length");
                var length = length_el.value;
                if (CPANEL.validate.positive_integer(length) == false) {
                    length = 12;
                } else if (length < 10) {
                    length = 10;
                } else if (length > 18) {
                    length = 18;
                }
                length_el.value = length;
                options.length = length;

                if (YAHOO.util.Dom.get("generate_password_mixed_alpha").checked == true) {
                    options.uppercase = true;
                    options.lowercase = true;
                } else {
                    options.uppercase = YAHOO.util.Dom.get("generate_password_uppercase").checked;
                    options.lowercase = YAHOO.util.Dom.get("generate_password_lowercase").checked;
                }

                if (YAHOO.util.Dom.get("generate_password_mixed_nonalpha").checked == true) {
                    options.numbers = true;
                    options.symbols = true;
                } else {
                    options.numbers = YAHOO.util.Dom.get("generate_password_numbers").checked;
                    options.symbols = YAHOO.util.Dom.get("generate_password_symbols").checked;
                }

                return options;
            };

            // generate a new password and select the input field text when the user clicks the refresh text
            var generate_new_password = function() {
                YAHOO.util.Dom.get("generate_password_input_field").value = CPANEL.password.create_password(get_password_options());
            };
            if (this.beforeExtendPanel) {
                this.beforeExtendPanel();
                YAHOO.util.Dom.get("generate_password_input_field").value = CPANEL.password.create_password(get_password_options());
            }

            YAHOO.util.Event.on("generate_password_reload", "click", generate_new_password);

            // watch the advanced options inputs
            var password_options = [
                "generate_password_mixed_alpha", "generate_password_uppercase", "generate_password_lowercase",
                "generate_password_mixed_nonalpha", "generate_password_numbers", "generate_password_symbols"
            ];
            YAHOO.util.Event.on(password_options, "change", generate_new_password);
        }

    }; // end password object
} // end else statement

//--- end /usr/local/cpanel/base/cjt/password.js ---

//--- start /usr/local/cpanel/base/cjt/urls.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including urls.js!");
} else {

    /**
	The urls module contains URLs for AJAX calls.
	@module urls
*/

    /**
	The urls class URLs for AJAX calls.
	@class urls
	@namespace CPANEL
	@extends CPANEL
*/
    CPANEL.urls = {

        /**
		URL for the password strength AJAX call.<br />
		GET request<br />
		arg1: password=password
		@property password_strength
		@type string
	*/
        password_strength: function() {
            return CPANEL.security_token + "/backend/passwordstrength.cgi";
        },

        // build a JSON API call from an object
        json_api: function(object) {

            // build the query string
            var query_string = "";
            for (var item in object) {
                if (object.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(object[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/json-api/cpanel?" + query_string;
        },

        // build a JSON API call from an object
        uapi: function(module, func, args) {

            // build the query string
            var query_string = "";
            for (var item in args) {
                if (args.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(args[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/execute/" + module + "/" + func + "?" + query_string;
        },

        whm_api: function(script, params, api_mode) {
            if (!api_mode) {
                api_mode = "json-api";
            } else if (api_mode == "xml") {
                api_mode = "xml-api";
            }

            // build the query string
            // TODO: turn this into a general object->query string function
            // 		 also have a query params -> object function
            var query_string = "";
            for (var item in params) {
                if (params.hasOwnProperty(item)) {
                    query_string += encodeURIComponent(item) + "=" + encodeURIComponent(params[item]) + "&";
                }
            }

            // add some salt to prevent browser caching
            query_string += "cache_fix=" + new Date().getTime();

            return CPANEL.security_token + "/" + api_mode + "/" + script + "?" + query_string;
        }

    }; // end urls object
} // end else statement

//--- end /usr/local/cpanel/base/cjt/urls.js ---

//--- start /usr/local/cpanel/base/cjt/util.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including util.js!");
} else {

    /**
    The util module contains miscellaneous utilities.
    @module array
*/

    /**
    The util module contains miscellaneous utilities.
    @class util
    @namespace CPANEL
    @extends CPANEL
*/
    if (!("util" in CPANEL)) {
        CPANEL.util = {};
    }
    (function() {

        var _wrap_template = "<wbr><span class=\"wbr\"></span>";

        var _wrap_callback = function(match) {
            return match.html_encode() + _wrap_template;
        };

        var IGNORE_KEY_CODES = {
            9: true, // tab
            13: true, // enter
            16: true, // shift
            17: true, // ctrl
            18: true // alt
        };
        var STOP_TYPING_TIMEOUT = 500;

        YAHOO.lang.augmentObject(CPANEL.util, {

            /**
             * Return the # of bytes that the string uses in UTF-8.
             *
             * @method  byte_length
             * @param str {String} The string whose byte length to compute.
             * @return {Number} the string's byte count
             */
            byte_length: (typeof Blob !== "undefined") ? function byte_length(str) {
                return (new Blob([str])).size;
            } : function byte_length(str) {
                return unescape(encodeURIComponent(str)).length;
            },

            // Catches the "enter" key when pressed in a text field.  Useful for simulating native <form> behavior.
            catch_enter: function(els, func) {

                // if func is a string, assume it's a submit button
                if (typeof (func) == "string") {
                    var submit_button = func;
                    var press_button = function() {
                        YAHOO.util.Dom.get(submit_button).click();
                    };
                    func = press_button;
                }

                var _catch_enter = function(e, o) {
                    var key = YAHOO.util.Event.getCharCode(e);
                    if (key == 13) {
                        o.func.call(this, e);
                    }
                };

                YAHOO.util.Event.on(els, "keydown", _catch_enter, {
                    func: func
                });
            },

            // initialize a second-decreasing countdown
            countdown_timeouts: [],
            countdown: function(el, after_func, args) {
                var seconds_el = YAHOO.util.Dom.get(el);
                if (!seconds_el) {
                    return;
                }

                var second_decrease = function() {
                    if (seconds_el) {
                        var seconds = parseInt(seconds_el.innerHTML);
                        if (seconds == 0) {
                            after_func(args);
                        } else {
                            seconds_el.innerHTML = seconds - 1;
                            CPANEL.util.countdown_timeouts[seconds_el.id] = setTimeout(second_decrease, 1000);
                        }
                    }
                };
                clearTimeout(this.countdown_timeouts[seconds_el.id]);
                this.countdown_timeouts[seconds_el.id] = setTimeout(second_decrease, 1000);
                return this.countdown_timeouts[seconds_el.id];
            },

            // add zebra stripes to a table, all arguments optional except el
            zebra: function(els, rowA, rowB, group_size) {
                if (!rowA) {
                    rowA = "rowA";
                }
                if (!rowB) {
                    rowB = "rowB";
                }
                if (!group_size) {
                    group_size = 1;
                }

                // if els is not an array make it one
                if (YAHOO.lang.isArray(els) == false) {
                    var el = els;
                    els = [el];
                }

                // initialize the row and group
                var row = rowA;
                var group_count = 0;

                for (var i = 0; i < els.length; i++) {
                    var table = YAHOO.util.Dom.get(els[i]);
                    var rows = YAHOO.util.Dom.getElementsByClassName("zebra", "", table);

                    for (var j = 0; j < rows.length; j++) {

                        // remove any existing row stripes
                        YAHOO.util.Dom.removeClass(rows[j], rowA);
                        YAHOO.util.Dom.removeClass(rows[j], rowB);

                        // add the stripe class
                        YAHOO.util.Dom.addClass(rows[j], row);
                        group_count++;

                        // alternate
                        if (group_count == group_size) {
                            group_count = 0;
                            row = (row == rowA) ? rowB : rowA;
                        }
                    }
                }
            },

            convert_breaklines: function(str) {
                return str.replace(/\n/, "<br />");
            },

            HTML_WRAP: _wrap_template,

            // A backport of "wrapFilter" from CJT2.
            //
            wrap_string_after_pattern_and_html_encode: function(string, pattern) {
                return string.replace(pattern, _wrap_callback);
            },

            // returns the value of the checked radio button
            // if no buttons are checked returns false
            get_radio_value: function(name, root) {
                if (!root) {
                    alert("Please provide a root element for the get_radio_value function to make it faster.");
                }
                var inputs = YAHOO.util.Dom.getElementsBy(function(el) {
                    return (YAHOO.util.Dom.getAttribute(el, "name") == name);
                }, "input", root);
                for (var i = 0; i < inputs.length; i++) {
                    if (inputs[i].checked) {
                        return inputs[i].value;
                    }
                }
                return false;
            },

            toggle_more_less: function(toggle_el, text_el, state) {
                toggle_el = YAHOO.util.Dom.get(toggle_el);
                text_el = YAHOO.util.Dom.get(text_el);
                if (!toggle_el || !text_el) {
                    alert("You passed non-existent elements to the CPANEL.util.toggle_more_less function.");
                    return;
                }
                if (!state) {
                    if (YAHOO.util.Dom.getStyle(text_el, "display") == "none") {
                        state = "more";
                    }
                }
                if (state == "more") {
                    CPANEL.animate.slide_down(text_el, function() {
                        toggle_el.innerHTML = LOCALE.maketext("less »");
                        CPANEL.align_panels_event.fire();
                    });
                } else {
                    CPANEL.animate.slide_up(text_el, function() {
                        toggle_el.innerHTML = LOCALE.maketext("more »");
                        CPANEL.align_panels_event.fire();
                    });
                }
            },

            keys: function(object) {
                var obj_keys = [];

                // no hasOwnProperty check here since we probably want prototype stuff
                for (var key in object) {
                    obj_keys.push(key);
                }
                return obj_keys;
            },

            values: function(object) {
                var obj_values = [];

                // no hasOwnProperty check here since we probably want prototype stuff
                for (var key in object) {
                    obj_values.push(object[key]);
                }
                return obj_values;
            },

            operating_system: function() {
                if (navigator.userAgent.search(/Win/) != -1) {
                    return "Windows";
                }
                if (navigator.userAgent.search(/Mac/) != -1) {
                    return "Mac";
                }
                if (navigator.userAgent.search(/Linux/) != -1) {
                    return "Linux";
                }
                return "Unknown";
            },

            toggle_unlimited: function(clicked_el, el_to_disable) {
                clicked_el = YAHOO.util.Dom.get(clicked_el);
                el_to_disable = YAHOO.util.Dom.get(el_to_disable);

                if (clicked_el.tagName.toLowerCase() != "input" || el_to_disable.tagName.toLowerCase() != "input") {
                    alert("Error in CPANEL.util.toggle_unlimited() function:\nInput arguments are not of type <input />");
                    return;
                }

                if (clicked_el.type.toLowerCase() == "text") {
                    YAHOO.util.Dom.removeClass(clicked_el, "disabled_text_input");
                    el_to_disable.checked = false;
                } else {
                    clicked_el.checked = true;
                    YAHOO.util.Dom.addClass(el_to_disable, "disabled_text_input");
                }
            },

            value_or_unlimited: function(text_input_el, radio_el, validation) {
                text_input_el = YAHOO.util.Dom.get(text_input_el);
                radio_el = YAHOO.util.Dom.get(radio_el);

                // add event handlers
                YAHOO.util.Event.on(text_input_el, "focus", function() {
                    radio_el.checked = false;
                    YAHOO.util.Dom.removeClass(text_input_el, "cjt_disabled_input");
                    validation.verify();
                });

                YAHOO.util.Event.on(radio_el, "click", function() {
                    radio_el.checked = true;
                    YAHOO.util.Dom.addClass(text_input_el, "cjt_disabled_input");
                    validation.verify();
                });

                // set initial state

            },

            // deep copy an object
            clone: function(obj) {
                var temp = YAHOO.lang.JSON.stringify(obj);
                return YAHOO.lang.JSON.parse(temp);
            },

            // prevent submitting the form when Enter is pressed on an <input> element
            prevent_submit: function(elem) {
                elem = YAHOO.util.Dom.get(elem);
                var stop_propagation = function(e) {
                    var key_code = YAHOO.util.Event.getCharCode(e);
                    if (key_code == 13) {
                        YAHOO.util.Event.preventDefault(e);
                    }
                };

                YAHOO.util.Event.addListener(elem, "keypress", stop_propagation);
                YAHOO.util.Event.addListener(elem, "keydown", stop_propagation);
            },

            get_text_content: function() {
                var lookup_property = CPANEL.has_text_content ? "textContent" : "innerText";
                this.get_text_content = function(el) {
                    if (typeof el === "string") {
                        el = document.getElementById(el);
                    }
                    return el[lookup_property];
                };
                return this.get_text_content.apply(this, arguments);
            },

            set_text_content: function() {
                var lookup_property = CPANEL.has_text_content ? "textContent" : "innerText";
                this.set_text_content = function(el, value) {
                    if (typeof el === "string") {
                        el = document.getElementById(el);
                    }
                    return (el[lookup_property] = value);
                };
                return this.set_text_content.apply(this, arguments);
            },

            // This registers an event to happen after STOP_TYPING_TIMEOUT has
            // passed after a keyup without a keydown. The event object is the
            // last keyup event.
            on_stop_typing: function(el, callback, obj, context_override) {
                el = DOM.get(el);

                var my_callback = (function() {
                    if (context_override && obj) {
                        return function(e) {
                            callback.call(obj, e);
                        };
                    } else if (obj) {
                        return function(e) {
                            callback.call(el, e, obj);
                        };
                    } else {
                        return function(e) {
                            callback.call(el, e);
                        };
                    }
                })();

                var search_timeout = null;
                EVENT.on(el, "keyup", function(e) {
                    if (!(e.keyCode in IGNORE_KEY_CODES)) {
                        clearTimeout(search_timeout);
                        search_timeout = setTimeout(my_callback, STOP_TYPING_TIMEOUT);
                    }
                });
                EVENT.on(el, "keydown", function(e) {
                    if (!(e.keyCode in IGNORE_KEY_CODES)) {
                        clearTimeout(search_timeout);
                    }
                });
            },

            // creates an HTTP query string from a JavaScript object
            // For convenience when assembling the data, we make null and undefined
            // values not be part of the query string.
            make_query_string: function(data) {
                var query_string_parts = [];
                for (var key in data) {
                    var value = data[key];
                    if ((value !== null) && (value !== undefined)) {
                        var encoded_key = encodeURIComponent(key);
                        if (YAHOO.lang.isArray(value)) {
                            for (var cv = 0; cv < value.length; cv++) {
                                query_string_parts.push(encoded_key + "=" + encodeURIComponent(value[cv]));
                            }
                        } else {
                            query_string_parts.push(encoded_key + "=" + encodeURIComponent(value));
                        }
                    }
                }

                return query_string_parts.join("&");
            },

            // parses a given query string, or location.search if none is given
            // returns an object corresponding to those values
            parse_query_string: function(qstr) {
                if (qstr === undefined) {
                    qstr = location.search.replace(/^\?/, "");
                }

                var parsed = {};

                if (qstr) {

                    // This rejects invalid stuff
                    var pairs = qstr.match(/([^=&]*=[^=&]*)/g);
                    var plen = pairs.length;
                    if (pairs && pairs.length) {
                        for (var p = 0; p < plen; p++) {
                            var key_val = pairs[p].split(/=/).map(decodeURIComponent);
                            var key = key_val[0].replace(/\+/g, " ");
                            if (key in parsed) {
                                if (typeof parsed[key] !== "string") {
                                    parsed[key].push(key_val[1].replace(/\+/g, " "));
                                } else {
                                    parsed[key] = [parsed[key_val[0]], key_val[1].replace(/\+/g, " ")];
                                }
                            } else {
                                parsed[key] = key_val[1].replace(/\+/g, " ");
                            }
                        }
                    }
                }

                return parsed;
            },

            get_numbers_from_string: function(str) {
                str = "" + str; // convert str to type String
                var numbers = str.replace(/\D/g, "");
                numbers = parseInt(numbers);
                return numbers;
            }

        }); // end util object

    }());

} // end else statement

//--- end /usr/local/cpanel/base/cjt/util.js ---

//--- start /usr/local/cpanel/base/cjt/ui/widgets/pager.js ---
/*
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof(CPANEL) === "undefined" || !CPANEL) {
    alert('You must include the CPANEL global object before including ui/widgits/pager.js!');
} else {

    (function() {

        // Define the namespace for this module
        CPANEL.namespace("CPANEL.ui.widgets");

        /**
    The pager module contains pager related objects used in cPanel.
    @module CPANEL.ui.widgets.pager
    */

        if (typeof(CPANEL.ui.widgets.pager) === 'undefined') {

            /**
        The PageActions enum contains the defined action flags reported to
        various action callbacks used by the PageManager class during events.
        @enum
        @static
        @class PagerActions
        @namespace CPANEL.ui.widgets */
            var PagerActions = {
                /**
            Signals to registered callbacks that this is a page size change event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CHANGE_PAGE_SIZE: 1,
                /**
            Signals to registered callbacks that this is a go to page event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                GO_TO_PAGE: 2,
                /**
            Signals to registered callbacks that this is a show all event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                SHOW_ALL: 4,
                /**
            Signals to registered callbacks that this is a clear filter event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CLEAR_FILTER: 8,
                /**
            Signals to registered callbacks that this is a clear sort event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CLEAR_SORT: 16,
                /**
            Signals to registered callbacks that this is a change filter event.
            @static
            @class PagerActions
            @property  CHANGE_FILTER */
                CHANGE_FILTER: 32,
                /**
            Signals to registered callbacks that this is a change sort event.
            @static
            @class PagerActions
            @property  CHANGE_SORT */
                CHANGE_SORT: 64
            };

            /**
        This class manages the parameters associated with each pager defined on a page. I is used as part of the
        common pagination system.
        @enum
        @static
        @class PagerManager
        @namespace CPANEL.ui.widgets */
            var PagerManager = function() {
                this.cache = {};
            };

            PagerManager.prototype = {
                /**
                 * Call back called before the manager fires an action.
                 * @class PagerManager
                 * @event
                 * @name beforeAction
                 * @param [String] scope- Unique name of the pager being initilized.
                 * @param [Hash] container - reference to the settings for the current pager.
                 * @param [PagerActions] action
                 */

                /**
                 * Call back called after the manager fires an action.
                 * @class PagerManager
                 * @event
                 * @name afterAction
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] container - reference to the settings for the current pager.
                 * @param [PagerActions] action
                 */

                /**
                 * Initialize the PageManager object for a specific scope
                 * @class PagerManager
                 * @name initialize
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] url - Optional alternative url. If same page, leave null.
                 * @param [Hash] params - Initial values for parameters passed to the url.
                 * @param [String] method - Either GET or POST
                 * @param [Hash] callbacks - Hash containing optional callbacks
                 *     Supported eveents include:
                 *     beforeAction - Called before the action triggers
                 *     afterAction - Called after the action triggers
                 */
                initialize: function(scope, url, params, method, callbacks) {
                    var container = {
                        url: url || "",
                        params: params || {},
                        method: method || "GET",
                        callbacks: {}
                    };

                    if (callbacks) {
                        if (callbacks.beforeAction) {
                            container.callback.beforeAction = callbacks.beforeAction;
                        }
                        if (callbacks.afterAction) {
                            container.callback.afterAction = callbacks.afterAction;
                        }
                    }

                    this.cache[scope] = container;
                },

                /**
                 * Sets the callbacks for a specific pager.
                 * @class PagerManager
                 * @name setCallback
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] callbacks - Hash containing optional callbacks
                 *     Supported eveents include:
                 *     beforeAction - Called before the action triggers
                 *     afterAction - Called after the action triggers
                 */
                setCallback: function(scope, callbacks) {
                    var container = this.cache[scope];
                    if (container && callbacks) {
                        if (callbacks.beforeAction) {
                            container.callback.beforeAction = callbacks.beforeAction;
                        }
                        if (callbacks.afterAction) {
                            container.callback.afterAction = callbacks.afterAction;
                        }
                    }
                },

                /**
                 * Sets the parameters for a specific pager.
                 * @class PagerManager
                 * @name setParameters
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] params - Name value pairs that you want to set. Items in the current params cache that are not specified in this argument are not changed or removed.
                 */
                setParameters: function(scope, params) {
                    if (params) {
                        var container = this.cache[scope];
                        for (var p in params) {
                            container.params[p] = params[p];
                        }
                    }
                },

                /**
                 * Gets the parameters for a specific pager.
                 * @class PagerManager
                 * @name getParameters
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Array] params - Names of the paramters you want to get.
                 * @return [Hash] - name value pairs in a hash.
                 */
                getParameters: function(scope, params) {
                    var output = {};
                    if (params) {
                        var container = this.cache[scope];
                        for (var i = 0, l = params.length; i < l; i++) {
                            var key = params[i];
                            output[key] = container.params[key];
                        }
                    }
                    return output;
                },
                /**
                 * Sets the specific parameter to the specific value for a specific pager.
                 * @class PagerManager
                 * @name setParameter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] name - Name of the parameter to set.
                 * @param [String] value - Value of the paramter.
                 */
                setParameter: function(scope, name, value) {
                    var container = this.cache[scope];
                    container.params[name] = value;
                },
                /**
                 * Gets the specific parameter for a specific pager.
                 * @class PagerManager
                 * @name getParameter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] name - Name of the parameter to set.
                 *
                 */
                getParameter: function(scope, name) {
                    var container = this.cache[scope];
                    return container.params[name];
                },
                /**
                 * Fires the go to page event.
                 * @class PagerManager
                 * @name fireGoToPage
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Number] start - Start index of first item on a page...
                 * @param [Number] page - Page to go to.
                 * @param [Number] skip - Number of pages to skip.
                 * @note There is signifigant data redundancy in the current implementation to track
                 * all three of these, likely only one is needed, but there seems to be dependancies
                 * on each in various code modules. Consider refactoring this when we have more time.
                 * @refactor
                 */
                fireGoToPage: function(scope, start, page, skip) {
                    var container = this.cache[scope];
                    container.params["api2_paginate_start"] = start;
                    container.params["page"] = page;
                    container.params["skip"] = skip;
                    return this.fireAction(scope, container, PagerActions.GO_TO_PAGE);
                },
                /**
                 * Fires the change items per page event.
                 * @class PagerManager
                 * @name fireChangePageSize
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Number] itemsperpage - Number of items per page.
                 */
                fireChangePageSize: function(scope, itemsperpage, submit) {
                    var container = this.cache[scope];
                    container.params["itemsperpage"] = itemsperpage;
                    if (submit) {
                        return this.fireAction(scope, container, PagerActions.CHANGE_PAGE_SIZE);
                    }
                    return true;
                },
                /**
                 * Fires the show all pages event.
                 * @class PagerManager
                 * @name fireShowAll
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Boolean] clearFilterSort - If true clear the filter and sort, otherwise, leaves them in tact.
                 *  Must implement this action on the server.
                 */
                fireShowAll: function(scope, clearFilterSort) {
                    var container = this.cache[scope];
                    container.params["viewall"] = clearFilterSort ? "1" : "0";
                    return this.fireAction(scope, container, clearFilterSort ? PagerActions.SHOW_ALL | PagerActions.CLEAR_FILTER | PagerActions.CLEAR_SORT : PagerActions.SHOW_ALL);
                },
                /**
                 * Fires the change page filter event.
                 * @class PagerManager
                 * @name fireChangeFilter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] searchregex - The new search expression.
                 * @param [Hash] params - Additional name/value pairs to add to the request, normally additional or custom filter tags.
                 */
                fireChangeFilter: function(scope, searchregex, params) {
                    var container = this.cache[scope];
                    container.params["searchregex"] = searchregex;
                    // Merge in the additianal parameters
                    for (var p in params) {
                        container.params[p] = params[p];
                    }
                    return this.fireAction(scope, container, PagerActions.CHANGE_FILTER);
                },
                /**
                 * Fires the change page sort event.
                 * @class PagerManager
                 * @name fireChangeSort
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] column - The name of the column to sort on.
                 * @param [String] direction - Either 'ascending' or 'descending'.
                 * @param [Hash] params - Additional name/value pairs to add to the request, normally additional or custom filter tags.
                 */
                fireChangeSort: function(scope, column, direction, params) {
                    var container = this.cache[scope];
                    container.params["api2_sort_column"] = column;
                    container.params["api2_sort_reverse"] = direction;
                    // Merge in the additianal parameters
                    for (var p in params) {
                        container.params[p] = params[p];
                    }
                    return this.fireAction(scope, container, PagerActions.CHANGE_SORT);
                },
                /**
                 * Fires the specified event including any optional beforeAction() and afterAction()
                 * handlers.
                 * @class PagerManager
                 * @name fireAction
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Object] container - Container for this scope holding all the arguments for the call
                 * @param [PagerAction] action - Action triggering this event.
                 */
                fireAction: function(scope, container, action) {
                    var cancel = false;

                    // Call the before action handler if its available
                    if (container.callbacks["beforeAction"]) {
                        cancel = container.callbacks["beforeAction"](scope, container, action);
                    }

                    if (cancel) {
                        return false;
                    }

                    var href = container.href || window.location.href.split('?')[0];
                    if (container.method == "GET") {
                        window.location = this._makeQuery(href, this._getQuery(container));
                    } else if (container.method === "POST") {
                        var form = this._buildForm(url, container.params);
                        if (form) {
                            form.submit();
                        }
                    }

                    // Call the after action handler if its available
                    if (container.callbacks["afterAction"]) {
                        container.callbacks["afterAction"](scope, container, action);
                    }
                    return true;
                },
                /**
                 * Converts the cached parameters into a URL querystring.
                 * @class PagerManager
                 * @name getQuery
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @return [String] - Query string generated from the current list of parameters for the specificed pager.
                 */
                getQuery: function(scope) {
                    var container = this.cache[scope];
                    return this._getQuery(container);
                },
                /**
                 * Converts the cached parameters into a URL querystring.
                 * @private
                 * @class PagerManager
                 * @name _getQuery
                 * @param [Object] container - Container with parameters for a given scope.
                 * @return [String] - Query string generated from the current list of parameters for the specificed pager.
                 */
                _getQuery: function(container) {
                    return this._serialize(container.params);
                },
                /**
                 * Builds a complete url for a GET call
                 * @private
                 * @class PagerManager
                 * @name _makeQuery
                 * @param [String] url
                 * @param [String] query
                 * @return [String] full URL.
                 */
                _makeQuery: function(url, query) {
                    return url + (query ? "?" + query : "");
                },
                /**
                 * Builds a complete form to submit via post. First checks to see if
                 * there is an old version of itself and removes it. It the injects the
                 * form into the DOM and returns a reference to it.
                 * @private
                 * @class PagerManager
                 * @name _buildForm
                 * @param [String] url
                 * @param [String] params
                 * @return [HTMLElement] form element generated for the url and parameters.
                 */
                _buildForm: function(url, params) {
                    var form = document.createElement("form");
                    form.href = url;
                    form.method = "POST";
                    form.id = scope + "-page-form";
                    for (var param in params) {
                        if (typeof(param) === "string") {
                            var input = document.createElement("input");
                            input.type = "hidden";
                            input.id = scope + "-page-param-" + param;
                            input.name = param;
                            input.value = params[param];
                            form.appendChild(input);
                        }
                    }

                    // Remove the older version of it so we don't bloat the webpage
                    var oldForm = document.getElementById(form.id);
                    if (oldForm) {
                        this._removeElement(oldForm);
                    }

                    // Inject it into the document so its live
                    document.appendChild(form);
                    return form;
                },
                /**
                 * Converts a hash into a URI compatible query string.
                 * @private
                 * @class PagerManager
                 * @name _serialize
                 * @param [Hash] obj
                 * @return [String] URI compatible querystring.
                 * @source http://stackoverflow.com/questions/1714786/querystring-encoding-of-a-javascript-object
                 */
                _serialize: function(obj) {
                    var str = [];
                    for (var p in obj)
                        str.push(encodeURIComponent(p) + "=" + encodeURIComponent(obj[p]));
                    return str.join("&");
                },
                /**
                 * Removes the element from it parent node if it has a parent.
                 * @private
                 * @class PagerManager
                 * @name _removeElement
                 * @param [HTMLElement] el
                 */
                _removeElement: function(el) {
                    var parent = el.parentNode;
                    if (parent) {
                        parent.removeChild(el);
                    }
                }
            };

            // Exports
            CPANEL.ui.widgets.PagerActions = PagerActions;
            CPANEL.ui.widgets.pager = new PagerManager();
        }

    })();
}

//--- end /usr/local/cpanel/base/cjt/ui/widgets/pager.js ---

//--- start /usr/local/cpanel/base/cjt/validate.js ---
// Copyright 2023 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/* jshint eqeqeq:false,-W108,-W089 */
/* eslint-disable camelcase, no-use-before-define */

/**
    The validate module contains a validator class and methods used to validate user input.
    @module validate
*/
(function() {
    "use strict";

    function _log(text) {
        if (window.console && window.console.log) {
            window.console.log(arguments);
        }
    }

    function _trace() {
        if (window.console && window.console.trace) {
            window.console.trace(arguments);
        }
    }

    /**
     * Validate the local part of a username for an account.
     * Its everything before the @ symbol.
     * @private
     * @param  {String}  text             Text to validate
     * @param  {String}  spec             Name of the validation rules to use: rfc or cpanel
     * @param  {Boolean} charCheckOnly    When true, the validator ony checks the character regex
     * @return {Boolean}                  true if the text is valid, false otherwise.
     */
    function _validate_local_part(text, spec, charCheckOnly) {

        // Initialize the parameters
        spec = spec || "rfc";
        text = text || "";
        charCheckOnly = !!charCheckOnly;

        // If text is empty, it's not a valid email but
        // doesn't contain any illegal characters either
        if (text === "") {
            return charCheckOnly;
        }

        // Validate the inputs
        if (spec !== "cpanel" && spec !== "rfc") {
            throw ("CPANEL.validate.local_part_email: invalid spec argument!");
        }

        // text must contain only these characters
        var pattern;
        if (spec === "rfc") {
            pattern = new RegExp("[^.a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]");
        } else {

            // This is the current set of chars allowed when creating a new cPanel email address
            pattern = new RegExp("[^.a-zA-Z0-9_-]");
        }

        if (pattern.test(text) === true) {
            return false;
        }

        if (charCheckOnly) {
            return true;
        }

        if (spec === "rfc") {

            // NOTE: These are broken out on individual pages for cpanel validators.

            // if the text has '.' as the first or last character then it's not valid
            if (text.charAt(0) === "." || text.charAt(text.length - 1) === ".") {
                return false;
            }

            // if the texting contains '..' then it's not valid
            if (/\.\./.test(text) === true) {
                return false;
            }
        }

        return true;
    }

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL === "undefined" || !CPANEL) {
        _log("You must include the CPANEL global object before including validate.js!");
    } else {

        /**
            The validate class contains the validator class and methods used to validate user input.<br />
            @class validate
            @namespace CPANEL
            @extends CPANEL
        */
        CPANEL.validate = {

            hide_validation_summary: false,

            // To be .concat()ed onto an array that already contains the context el ID.
            // This registers an Overlay instance that is intended to update with
            // various page changes.
            // NOTE: This can't run at page-load time because CJT's CLDR data is loaded
            //* after* the rest of CJT.
            get_page_overlay_context_arguments: function() {
                var overlay_anchor;
                var form_el_anchor;
                if (LOCALE.is_rtl()) {
                    overlay_anchor = "tr";
                    form_el_anchor = "tl";
                } else {
                    overlay_anchor = "tl";
                    form_el_anchor = "tr";
                }

                return [overlay_anchor, form_el_anchor, ["beforeShow", "windowResize", CPANEL.align_panels_event]];
            },
            a: "",
            form_checkers: {},

            /**
                The validator class is used to provide validation to a group of &lt;input type="text" /&gt; fields.<br /><br />
                For example: You could use one validator object per fieldset and treat each fieldset group as one validation unit,
                or you create a validator object for each &lt;input type="text" /&gt; element on the page.  The class is designed to be flexible
                enough to work in any validation situation.<br /><br />
                HTML:<br />
                <pre class="brush: xml">
                &lt;form method="post" action="myform.cgi" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="text" id="user_name" name="user_name" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="text" id="user_email" name="user_email" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="submit" id="submit_user_info" value="Submit" /&gt;
                &lt;/form&gt;
                </pre>
                JavaScript:
                <pre class="brush: js">
                // create a new a validator object for my input fields
                var my_validator = new CPANEL.validate.validator("Contact Information Input");&#13;

                // add validators to the input fields
                my_validator.add("user_name", "min_length(%input%, 5)", "User name must be at least 5 characters long.");
                my_validator.add("user_name", "standard_characters", "User name must contain standard characters.  None of the following: &lt; &gt; [ ] { } \");
                my_validator.add("user_email", "email", "That is not a valid email address.");&#13;

                // attach the validator to the input fields (this adds automatic input validation when the user types in the field)
                my_validator.attach();&#13;

                // attach an event handler to the submit button in case they try to submit with invalid data
                YAHOO.util.Event.on("submit_info", "click", validate_form);&#13;

                // this function gets called when the submit button gets pressed
                function validate_form(event) {
                &nbsp;&nbsp;&nbsp;&nbsp;if (my_validator.is_valid() == false) {
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;YAHOO.util.Event.preventDefault(event);     // prevent the form from being submitted
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CPANEL.validate.show_modal_error( my_validator.error_messages() );  // show a modal error dialog box
                &nbsp;&nbsp;&nbsp;&nbsp;}
                &nbsp;&nbsp;&nbsp;&nbsp;else {
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;// the "event" function gets called and the form gets submitted (in practice you don't need the "else" clause)
                &nbsp;&nbsp;&nbsp;&nbsp;}
                };
                </pre>
                @class validator
                @namespace CPANEL.validate
                @constructor
                @param {string} title The title of the validator instance.  A human-readable title used to identify your validator against others that may be on the same page.
            */
            validator: function(title) {

                if (YAHOO.util.CustomEvent) {
                    this.validateSuccess = new YAHOO.util.CustomEvent("validateSuccess", this);
                    this.validateFailure = new YAHOO.util.CustomEvent("validateFailure", this);
                }

                /**
                    The title of the validator instance.  A human-readable title used to identify your validator against others that may be on the same page.
                    @property title
                    @type string
                    @for CPANEL.validate.validator
                */
                if (typeof (title) !== "string") {
                    _trace();
                    _log("You need to pass the title of the validator object into the constructor.\nie: var my_validator = new CPANEL.validate.validator(\"Email Account\");");
                    return;
                }
                this.title = title;

                /**
                    An array of validators.  Holds all the important information about your validator object.<br />
                    This value is public, but in practice you will probably never need to access it.  I left it public for all those cases I couldn't think of where someone might need to access it directly.
                    @property validators
                */
                this.validators = [];

                // A thin wrapper to allow addition of functions that indicate
                // invalidity by throwing an exception, where the exception
                // is the message to display.
                this.add_thrower = function(el, func) {
                    var msg;
                    var catcher = function() {
                        try {
                            func.apply(this, arguments);
                            return true;
                        } catch (err) {
                            msg = err;
                            return false;
                        }
                    };

                    return this.add(el, catcher, function() {
                        return msg;
                    });
                };

                /**
                    Adds an validator function to the validators array.<br />
                    <br />
                    example:<br />
                    <pre class="brush: js">
                    var my_validator = new CPANEL.validate.validator("My Validator");&#13;

                    // add a function literal; here I'm assuming my_custom_function is defined elsewhere
                    // remember that your custom function should return true or false
                    my_validator.add("input_element", function() { my_custom_function(DOM.get("input_element").value) }, "My custom error message.");&#13;

                    // if the second argument is a string it's assumed to be a method of CPANEL.validate, in this case CPANEL.validate.url
                    my_validator.add("input_element", "url('httq://yahoo.com')", "That is not a valid URL.");&#13;

                    // if the second argument has no parenthesis it's assumed to call the value of the input element
                    // in this case CPANEL.validate.email( YAHOO.util.Dom.get("input_element").value )
                    my_validator.add("input_element", "email", "That is not a valid email address.");&#13;

                    // use %input% to refer to the element's value: YAHOO.util.Dom.get("input_element").value
                    my_validator.add("input_element", "if_not_empty(%input%, CPANEL.validate.url)", "That is not a valid url.");
                    my_validator.add("input_element", "min_length(%input%, 5)", "Input must be at least 5 characters long.");
                    </pre>

                    NOTE: If an *_error element has a “no_panel” class, then the validation
                    messages are given as tooltips only rather than as overlays.
                    This can help to reduce clutter in the UI.

                    @method add
                    @param {DOM element} el a DOM element or id, gets passed to YAHOO.util.Dom.get
                    @param {string | function} func either a string or a function, WARNING: strings get eval'ed after some regex, see above for the syntax
                    @param {string | function} msg the error message to be shown when func returns false; should be localized already;
                */
                this.add = function(el, func, msg, conditional_func, opts) {
                    return this._do_add.apply(this, arguments);
                };

                /**
                    Add a function that will only trigger an error message on form submit.
                    The function will always fire, but if its error is the only error, then the error message
                    will not appear, and the validation is hidden. This allows avoiding telling users that
                    "you must do this before submission!!" when they may well be about to do that very thing.

                    Same interface as for this.add().
                    XXX: The flag-passing is an expedience. Ideal would be separate lists of validator items,
                    but that would require change throughout this module. This is a new feature added to
                    legacy code, so minimal change is ideal.
                */
                this.add_for_submit = function(el, func, msg, conditional_func, opts) {
                    opts = opts || {};
                    opts.submit_only = true;
                    return this._do_add(el, func, msg, conditional_func, opts);
                };

                this._do_add = function(orig_el, func, msg, conditional_func, opts) {

                    // verify that the element exists in the DOM
                    var el = YAHOO.util.Dom.get(orig_el);
                    if (!el) {
                        _trace();
                        _log("Error in CPANEL.validate.add: could not find element '" + orig_el + "' in the DOM");
                        return;
                    }

                    var error_element_id = el.id + "_error";
                    var error_el = YAHOO.util.Dom.get(error_element_id);

                    // if the id_error div/span does not exist, show an error
                    if (!error_el) {
                        _trace();
                        _log("Error in CPANEL.validate.add: could not find element '" + error_element_id + "' in the DOM");
                        return;
                    }

                    // make sure the error element is 16x16
                    if (!opts || opts && !opts.no_width_height) {
                        YAHOO.util.Dom.setStyle(error_el, "width", "16px");
                        YAHOO.util.Dom.setStyle(error_el, "height", "16px");
                    }

                    // if the error element is an image make it transparent
                    if (error_el.tagName.toLowerCase() === "img") {
                        error_el.src = CPANEL.icons.transparent_src;
                        YAHOO.util.Dom.setStyle(error_el, "vertical-align", "middle");
                    }

                    // check that the error message is either a string or a function
                    if (typeof (msg) !== "string" && typeof (msg) !== "function") {
                        _log("Error in CPANEL.validate.add: msg must be either a string or a function");
                        return;
                    }

                    // if they have not specified a conditional function, create one that evaluates to true (ie: their validator will always execute)
                    if (!conditional_func) {
                        conditional_func = function() {
                            return true;
                        };
                    } else if (typeof (conditional_func) === "string") {

                        // if the conditional function is a string assume it is a radio or checkbox
                        // TODO: add support for <select><option> elements

                        var conditional_el = YAHOO.util.Dom.get(conditional_func);
                        if (!conditional_el) {
                            _log("Error in CPANEL.validate.add: could not find element '" + conditional_func + "' in the DOM.");
                            return;
                        }

                        var attribute_type = conditional_el.getAttribute("type");
                        if (attribute_type === "radio" || attribute_type === "checkbox") {
                            conditional_func = function() {
                                return conditional_el.checked;
                            };
                        } else {
                            _log("Error in CPANEL.validate.add: conditional function argument '" + conditional_el.id + "'must be a DOM element of type \"radio\" or \"checkbox\"");
                            return;
                        }
                    }

                    // if func is a string convert it to a function
                    if (typeof (func) === "string") {

                        // if func is a string assume it's a method of CPANEL.validate
                        // example syntax: validator_object.add("my_element", "url('http://yahoo.com')", "that is not a valid url");
                        func = "CPANEL.validate." + func;

                        // TODO: check that the string is a valid CPANEL.validate function

                        // if the string does not contain any parenthesis assume it is a method that calls the input of the object passed into it
                        // example syntax: validator_object.add("my_element", "url", "that is not a valid url");
                        if (func.match(new RegExp(/[()]/)) === null) {
                            func = func + "(%input%)";
                        }

                        // replace %input% with the element value
                        // example syntax:  validator_object.add("my_element", "if_not_empty(%input%, CPANEL.validate.url)", "that is not a valid url");
                        //                  validator_object.add("my_element", "min_length(%input%, 5)", "input must be at least 5 characters long");
                        func = func.replace(/(\$input\$)|(%input%)/i, "YAHOO.util.Dom.get(\"" + el.id + "\").value");

                        // convert func to a function literal
                        // NOTE: use of eval() here; please modify this code with caution
                        try {

                            // NOTE: This has to be left in for legacy. Ick.
                            /* jshint evil:true */
                            eval("func = function() { return " + func + "; };");
                        } catch (e) {
                            _log("Error in CPANEL.validate.add: Error eval()ing your function argument");
                            return;
                        }
                    }

                    // add the validator to the array
                    this.validators.push({
                        el: el,
                        func: func,
                        msg: msg,
                        conditional_func: conditional_func,
                        submit_only: opts && opts.submit_only,
                        unique_id: opts && opts.unique_id,
                    });
                };

                /**
                    Attaches the validator functions to their respective DOM elements (ie: adds event handlers to the input fields).
                    @method attach
                */
                this.attach = function() {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements and add event handlers and error panels
                    for (var i = 0; i < elements.length; i++) {

                        // grab the validate functions and error messages for this element
                        var element = elements[i];

                        // add the event handler if necessary
                        // if type attribute is null get the tagName to test for textarea
                        var attribute_type = element.type || element.tagName;

                        // if the input has an internal cursor:
                        if (/password|text|textarea|number/i.test(attribute_type)) {
                            if (CPANEL.dom.has_oninput) {
                                EVENT.on(element, "input", verify_element, {
                                    el: element,
                                });
                            } else { // IE9 and earlier
                                EVENT.on(element, "keyup", verify_element, {
                                    el: element,
                                });
                                EVENT.on(element, "change", verify_element, {
                                    el: element,
                                });
                                EVENT.on(element, "paste", delayed_verify_element, {
                                    el: element,
                                });
                            }

                        // Input file and select require the change event
                        } else if (/file|select/i.test(attribute_type)) {
                            EVENT.on(element, "change", verify_element, {
                                el: element,
                            });
                        }

                        // add the error panel
                        create_error_panel(element);
                    }
                };

                /**
                    Removes all validators from their respective DOM elements (ie: removes the event handlers).<br />
                    WARNING: this will remove ALL event handlers for these elements; this is a limitation of YAHOO.util.Event
                    @method detach
                */
                this.detach = function() {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements remove the event handlers
                    for (var i = 0; i < elements.length; i++) {
                        if (CPANEL.dom.has_oninput) {
                            EVENT.purgeElement(elements[i], false, "input");
                        } else { // IE8
                            EVENT.purgeElement(elements[i], false, "keyup");
                            EVENT.purgeElement(elements[i], false, "change");
                            EVENT.purgeElement(elements[i], false, "paste");
                        }
                    }
                    this.clear_messages();
                };

                /**
                    Returns the current validation state for all the validators in the array.
                    @method is_valid
                    @return {boolean} returns true if all the validator functions return true
                */
                this.is_valid = function() {
                    for (var i = 0; i < this.validators.length; i++) {
                        if (this.validators[i].el.disabled) {
                            continue;
                        }
                        if (this.validators[i].conditional_func(this.validators[i].el, this.validators[i])) {
                            if (!this.validators[i].func(this.validators[i].el, this.validators[i])) {
                                return false;
                            }
                        }
                    }

                    return true;
                };

                /**
                    Returns an object of all the error messages for currently invalid input.<br />
                    Useful for modal error boxes.
                    @method error_messages
                    @return {object} an object of error messages in the format: <code>&#123; title:"title", errors:["error message 1","error message 2"] &#125;</code><br />false if the the input is valid
                */
                this.error_messages = function() {

                    // loop through the validators and get all the error messages
                    var error_messages = [];
                    for (var i = 0; i < this.validators.length; i++) {
                        if (this.validators[i].conditional_func(this.validators[i].el, this.validators[i])) {
                            if (!this.validators[i].func(this.validators[i].el, this.validators[i])) {
                                error_messages.push(_process_error_message(this.validators[i].msg, this.validators[i].el));
                            }
                        }
                    }

                    // no error messages, return false
                    if (error_messages.length === 0) {
                        return false;
                    }

                    return {
                        title: this.title,
                        errors: error_messages,
                    };
                };

                /**
                    Clears all validation status messages.
                    @method clear_messages
                */
                this.clear_messages = function() {
                    for (var i = 0; i < this.validators.length; i++) {
                        var error_element = YAHOO.util.Dom.get(this.validators[i].el.id + "_error");

                        if (!error_element) {
                            continue;
                        }

                        if (error_element.tagName.toLowerCase() === "img") {
                            error_element.src = CPANEL.icons.transparent_src;
                        } else {
                            error_element.innerHTML = "";
                        }
                    }
                    hide_all_panels();
                };

                /**
                    Shows validation success or errors on the page by updating the DOM.
                    Useful when initially loading a page or for showing failure on a form submit button.
                    @method verify
                */
                this.verify = function(evt) {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements and verify each one
                    for (var i = 0; i < elements.length; i++) {
                        verify_element(null, {
                            el: elements[i],
                            "event": evt,
                        });
                    }
                };

                /**
                    Same as verify(), but this sends in a mock submit "event" that
                    will trigger display of submit-only validation messages.
                */
                this.verify_for_submit = function() {
                    return this.verify({
                        type: "submit",
                    });
                };

                /*
                    PRIVATE MEMBERS
                    Note: Yuidoc ignores private member documentation, but I included it in the same format for consistency.
                */

                /**
                    Use "that" if you need to reference "this" object.  See http://www.crockford.com/javascript/private.html for more information.
                    @property that
                    @private
                */
                var that = this;

                // private object to hold the error panels
                var panels = {};

                /**
                    Creates an error YUI panel.
                    @method create_error_panel
                    @param {DOM element} The input element the error panel is for.
                    @private
                */
                var create_error_panel = function(element) {

                    // TODO: need to check to make sure we're not creating a new panel on top of one that already exists

                    // This was originally written to use Panel, but Overlay is the better choice.
                    // Unfortunate to put "Overlay" objects into the "panels" container,
                    // and also for them to have a class of "validation_error_panel",
                    // but it's the best way forward for now.
                    var overlay_config = {
                        visible: false,
                        zindex: 1000,
                        context: [element.id + "_error"].concat(CPANEL.validate.get_page_overlay_context_arguments()),
                    };
                    DOM.addClass(element.id + "_error", "cjt_validation_error");
                    panels[element.id] = new YAHOO.widget.Overlay(element.id + "_error_panel", overlay_config);
                    panels[element.id].setBody("");

                    // Done to make sure the validations scroll with content container in whm.
                    // Currently this ID is not being used in either cPanel and/or Webmail.
                    var contentContainer = document.getElementById("contentContainer");
                    if (contentContainer) {
                        panels[element.id].render(contentContainer);
                    } else {
                        panels[element.id].render(document.body);
                    }


                    // add the "validation_error_panel" style class to the overlay
                    YAHOO.util.Dom.addClass(element.id + "_error_panel", "validation_error_panel");
                };


                /**
                 *   Clear visuals for one validator
                 *
                 *   @method clear_one_message
                 *   @param element {String | DOMNode} The element whose validation indicators we need to clear.
                 */
                var clear_one_message = function(element) {
                    var error_element = DOM.get(element.id + "_error");
                    var no_panel = DOM.hasClass(error_element, "no_panel");

                    if (error_element.tagName.toLowerCase() === "img") {
                        error_element.src = "data:image/png,";

                        if (no_panel) {
                            error_element.title = "";
                        }
                    } else {
                        error_element.innerHTML = "";
                    }

                    if (panels[element.id]) {
                        panels[element.id].hide();
                    }
                };


                var delayed_verify_element = function(e, o) {
                    setTimeout(verify_element.bind(this, e, o), 5);
                };

                /**
                    Checks an element's input against a set of functions
                    @method verify_element
                    @param {object} o object handler
                    @param {object} params object with the element to be checked, the functions to check it against, and the error messages to be displayed on failure
                    @private
                */
                var verify_element = function(e, o) {
                    if (o.el.disabled) {
                        return;
                    }

                    var submit_only_function_failed_outside_submit;

                    var this_is_a_submit;
                    if (o.event) {
                        var evt = o.event;

                        // This doesn't really fire because we don't actually attach to the "submit" event,
                        // but it's a good idea to have this listener anyway.
                        this_is_a_submit = (evt.type === "submit");

                        // We actually attach to the submit button's "click" event so that
                        // we can prevent the form's onsubmit from firing if the validation fails.
                        // That means we have to be a bit smarter about detecting whether we're in
                        // a submission, though.
                        if (!this_is_a_submit && (evt.type === "click")) {
                            var clickee = EVENT.getTarget(evt);
                            var tag_name = clickee.tagName.toLowerCase();
                            this_is_a_submit = (clickee.type === "submit") && ((tag_name === "button") || (tag_name === "input"));
                        }
                    }

                    // grab all the error messages from functions that are not valid
                    var error_messages = [];
                    var ids = [];
                    for (var i = 0; i < that.validators.length; i++) {
                        var validation_unit = that.validators[i];
                        if (validation_unit.el.id !== o.el.id) {
                            continue;
                        }

                        if (validation_unit.conditional_func(o.el, that.validators[i])) {
                            if (!validation_unit.func(o.el, that.validators[i])) {
                                if (!this_is_a_submit && validation_unit.submit_only) {
                                    submit_only_function_failed_outside_submit = true;
                                } else {
                                    error_messages.push(that.validators[i].msg);
                                    ids.push(that.validators[i].unique_id);
                                }
                            }
                        }
                    }

                    // show success or error
                    if (error_messages.length === 0) {

                        // Validation *did* fail; we just don't want to tell the user
                        // about it since we aren't in a form submission.
                        // ex.: We require a field "A" in a form to have a value.
                        // Field "A"'s validity depends on the value of field "B",
                        // so every time we change field "B"'s value we also need to
                        // fire field "A"'s validator. BUT, we don't want to complain
                        // about field "A" not having a value in this case since we can
                        // assume that the user is about to fill that field out. Only
                        // on page submission do we actually show the validation message
                        // that says, "you must fill this out".
                        if (submit_only_function_failed_outside_submit) {
                            clear_one_message(o.el);
                            that.validateFailure.fire({
                                is_submit_only_failure: true,
                            });
                        } else {
                            show_success(o.el);
                            that.validateSuccess.fire();
                        }
                    } else {
                        show_errors(o.el, error_messages, ids);
                        that.validateFailure.fire({
                            is_submit_only_failure: false,
                        });
                    }
                };

                /**
                    Show a successful input validation
                    @method show_success
                    @param {DOM element} element input element
                    @private
                */
                var show_success = function(element) {
                    var error_element = YAHOO.util.Dom.get(element.id + "_error");
                    if (YAHOO.util.Dom.getStyle(error_element, "display") !== "none") {

                        // hide the panel if it is showing
                        panels[element.id].hide();

                        // show the success icon
                        if (error_element.tagName.toLowerCase() === "img") {
                            error_element.src = CPANEL.icons.success_src;
                        } else {
                            error_element.innerHTML = CPANEL.icons.success;
                        }

                        error_element.title = "";

                        // purge the element of event handlers that pop up panels
                        YAHOO.util.Event.purgeElement(error_element, false);
                    }
                };

                // show input validation errors
                var show_errors = function(element, messages, ids) {
                    messages = messages.map(function(cur_msg) {
                        return _process_error_message(cur_msg, element);
                    });

                    // get the error element
                    var error_element = YAHOO.util.Dom.get(element.id + "_error");

                    // if the error element is hidden do not show anything
                    if (YAHOO.util.Dom.getStyle(error_element, "display") === "none") {
                        return;
                    }

                    var no_panel = YAHOO.util.Dom.hasClass(error_element, "no_panel");
                    var img_title;
                    if (no_panel) {
                        var dummy_span = document.createElement("span");
                        img_title = [];
                        for (var m = 0; m < messages.length; m++) {
                            dummy_span.innerHTML = messages[m];
                            img_title.push(dummy_span.textContent || dummy_span.innerText);
                        }
                        img_title = img_title.join("\n");
                    }

                    // show the error image
                    if (error_element.tagName.toLowerCase() === "img") {
                        error_element.src = CPANEL.icons.error_src;
                        if (no_panel) {
                            error_element.title = img_title;
                        }
                    } else {
                        error_element.innerHTML = CPANEL.icons.error;
                        if (no_panel) {
                            error_element.getElementsByTagName("img")[0].title = img_title;
                        }
                    }

                    // do not show the panel if the "no_panel" class exists
                    if (no_panel) {
                        return;
                    }

                    // add the validation errors to the panel
                    var panel_body = '<div class="validation_errors_div">';
                    panel_body += '<ul class="validation_errors_ul">';
                    for (var i = 0; i < messages.length; i++) {
                        var id = (ids[i] ? ' id="' + ids[i] + '"' : "" );
                        panel_body += '<li class="validation_errors_li"' + id + ">" + _process_error_message(messages[i], element) + "</li>";
                    }
                    panel_body += "</ul></div>";

                    // display the messages directly in the error element if the "show_inline" class exists
                    var show_inline = YAHOO.util.Dom.hasClass(error_element, "show_inline");
                    if (show_inline) {
                        error_element.innerHTML = panel_body;
                    } else {
                        panels[element.id].setBody(panel_body);
                        panels[element.id].show();
                    }

                };

                // hide all error panels
                var hide_all_panels = this.hide_all_panels = function() {
                    for (var i in panels) {
                        panels[i].hide();
                    }
                };

                // returns an array of unique elements
                var _get_unique_elements = function() {
                    return that.validators.map(function(v) {
                        return v.el;
                    }).unique();
                };

                // processes an error message
                var _process_error_message = function(msg, element) {

                    // msg is a string
                    if (typeof (msg) === "string") {
                        return msg;
                    }

                    // msg is a function
                    return msg(element);
                };

            }, // end validator object

            /**
                Shows a modal error box.<br />
                ProTip: Use the show_errors method of your validator object with this function.
                @method show_modal_error
                @for CPANEL.validate
                @param {object} messages an object of type: <code>&#123; title:"title", errors:["error message 1","error message 2"] &#125;</code> (can also be an array of this object type for when you have multiple validators on the same page)
            */
            show_modal_error: function(messages) {

                // convert messages to an array
                var temp = [];
                if (YAHOO.lang.isArray(messages) === false) {
                    temp.push(messages);
                    messages = temp;
                }

                // remove the panel if it already exists
                if (YAHOO.util.Dom.inDocument("validation_errors_modal_box") === true) {
                    var remove_me = YAHOO.util.Dom.get("validation_errors_modal_box");
                    remove_me.parentNode.removeChild(remove_me);
                }

                // create the panel
                var panel_options = {
                    width: "350px",
                    fixedcenter: true,
                    close: true,
                    draggable: false,
                    zindex: 1000,
                    modal: true,
                    visible: false,
                };
                var panel = new YAHOO.widget.Panel("validation_errors_modal_box", panel_options);

                // header
                var header = '<div class="lt"></div>';
                header += "<span>" + LOCALE.maketext("Validation Errors") + "</span>";
                header += '<div class="rt"></div>';
                panel.setHeader(header);

                // body
                var body = "";
                for (var i = 0; i < messages.length; i++) {
                    body += '<span class="validation_errors_modal_box_title">' + messages[i].title + "</span>";
                    body += '<ul class="validation_errors_modal_box_ul">';
                    var these_errors;
                    if (messages[i].errors instanceof Array) {
                        these_errors = messages[i].errors;
                    } else {
                        these_errors = [messages[i].errors];
                    }
                    for (var j = 0; j < these_errors.length; j++) {
                        body += '<li class="validation_errors_modal_box_li">' + these_errors[j] + "</li>";
                    }
                    body += "</ul>";
                }
                panel.setBody(body);

                // footer
                var footer = '<div class="lb"></div>' +
                    '<div class="validation_errors_modal_box_actions">' +
                    '<input id="validation_errors_modal_panel_close_button" type="button" class="input-button btn-primary" value="' + LOCALE.maketext("Close") + '" />' +
                    "</actions>" +
                    '<div class="rb"></div>';

                panel.setFooter(footer);

                // add the event handler and put the focus on the close button after the panel renders
                var after_show = function() {
                    YAHOO.util.Event.on("validation_errors_modal_panel_close_button", "click", function() {
                        panel.hide();
                    });
                    YAHOO.util.Dom.get("validation_errors_modal_panel_close_button").focus();
                };
                panel.showEvent.subscribe(after_show);

                // show the panel
                panel.render(document.body);
                panel.show();
            },

            /**
                Validates a form submission against validator objects.
                If the validator object(s) validate to true the form gets submitted, else the form submission is halted and a modal error box with the validation errors is shown.
                This method attaches an "onclick" event handler to the form submission element.
                @method attach_to_form
                @param {DOM element} el the id of the form submit button
                @param {object} validators a single validator object, an array of validator objects, or an object of validator objects
                // optional: If either opts.success_callback or opts is a function,
                // that function is executed upon successful validation.
            */
            attach_to_form: function(el, validators, opts) {
                var success_callback;
                if (opts) {
                    if (typeof opts === "function") {
                        success_callback = opts;
                    } else {
                        success_callback = opts.success_callback;
                    }
                } else {
                    opts = {};
                }

                var typeof_validator = function(obj) {
                    if (!obj ||
                        typeof (obj.add) !== "function" ||
                        typeof (obj.attach) !== "function" ||
                        typeof (obj.title) !== "string") {
                        return false;
                    }
                    return true;
                };

                // convert a single instance, array, or object of validators to an array
                var temp = [];
                if (typeof_validator(validators)) {
                    temp.push(validators);
                } else {
                    for (var i in validators) {
                        if (!typeof_validator(validators[i])) {
                            continue;
                        }
                        temp.push(validators[i]);
                    }
                }
                validators = temp;

                // check to see if the validator functions are valid
                CPANEL.validate.form_checkers[el] = function(event, checkonly) {
                    var messages = [],
                        topYCoord,
                        topElId;
                    var good_data = true;

                    // loop through the validators
                    for (var i = 0; i < validators.length; i++) {
                        validators[i].verify(event);
                        if (!validators[i].is_valid()) {
                            good_data = false;
                            messages.push(validators[i].error_messages());

                            var curElId;

                            for (let validator of validators[i].validators) {
                                curElId = validator.el.id;
                                let curElErrorPanel = document.getElementById(`${curElId}_error_panel`);
                                if (curElErrorPanel && curElErrorPanel.style.visibility === "visible") {
                                    curElId = `${curElId}_error`;
                                    break;
                                }
                            }

                            // An input that is hidden won't return a Y value so we have to go based on a known field.
                            var yPos = DOM.getY(curElId);
                            if (!topYCoord || yPos < topYCoord) {
                                topYCoord = yPos;
                                topElId = curElId;
                            }
                        }
                    }

                    // if the validators are not true, stop the default event and show the modal error panel
                    // also the optional callback function does not get called
                    if (good_data === false) {
                        if (event) {
                            EVENT.preventDefault(event);
                        }

                        if (!CPANEL.validate.hide_validation_summary ) {
                            if ( !opts.no_panel ) {
                                CPANEL.validate.show_modal_error(messages);
                            }
                        }

                        scrollToError:
                        if (!opts.no_animation && CPANEL.animate) {
                            let firstErrorInFormGroup = document.querySelector(`.form-group #${topElId}`);
                            let firstVisibleErrorPanel = document.querySelector("*[id$='_error_panel'][style*='visibility: visible']");

                            // Some pages don't have their error messages visually tucked within the form they apply to.
                            // For those situations, we'll just grab the actual message and scroll to it instead of the section holding it.
                            let firstErrorElement = firstErrorInFormGroup ? firstErrorInFormGroup.closest(".form-group") : firstVisibleErrorPanel;

                            // If we can't find the error, there's no need to run the rest of this block, so we break out.
                            if (!firstErrorElement) {
                                break scrollToError;
                            }

                            let viewportWidth = document.documentElement.clientWidth;
                            let pageHeader = document.querySelector("header");
                            let heightOfPageHeader = pageHeader.getBoundingClientRect().height;
                            let extraSpacing = 10;
                            let errorElVerticalDisplacement = firstErrorElement.getBoundingClientRect().top;
                            let errorElHorizontalDisplacement = firstErrorElement.getBoundingClientRect().right;
                            let verticalDisplacement = errorElVerticalDisplacement - heightOfPageHeader - extraSpacing;
                            let horizontalDisplacement =  errorElHorizontalDisplacement - viewportWidth;

                            // Using Math.abs on the horizontal displacement so we never scroll left.
                            window.scrollBy({
                                top: verticalDisplacement,
                                left: Math.abs(horizontalDisplacement),
                                behavior: "smooth",
                            });
                        }

                        return false;
                    }

                    // else the form submission event gets called inherently

                    if (!checkonly && success_callback) {
                        success_callback(event);
                    }

                    return true;
                };

                // NOTE: This fires *before* the form's submit event, and will fire
                // even if the form submits via pressing ENTER.
                // It's important that we attach to this event, NOT form "submit",
                // because if we attach to form "submit" then we can't prevent further
                // action on the submit event. Attaching here allows us to prevent
                // inline "onsubmit" events.
                YAHOO.util.Event.on(el, "click", CPANEL.validate.form_checkers[el]);
            },

            // create a validator object from a validation definition
            create: function(id, name, definition) {

                // check the id
                var el = YAHOO.util.Dom.get(id);
                if (!el) {
                    _log("Error in CPANEL.validate.create: id '" + el.id + "' does not exist in the DOM.");
                    return;
                }

                // check the definition
                if (!CPANEL.validation_definitions[definition]) {
                    _log("Error in CPANEL.validate.create: Validation definition '" + definition + "' does not exist.");
                    return;
                }

                var atoms = CPANEL.validate.util.get_atoms_from_definition(definition);
                var func = CPANEL.validate.util.create_function_from_atoms(atoms, el);
                var msg = CPANEL.validate.util.create_msg_from_atoms(atoms);

                var validator = new CPANEL.validate.validator(name);
                validator.add(id, func, msg);
                validator.attach();
                return validator;
            },

            /**
             * Validates that the text does not start with or end with a period and
             * does not contain two or more consecutive periods.
             * @param  {string} text
             * @return {boolean}     returns true if <code>text</code> is free of the
             * unsafe periods, and false if it starts with a period, or ends with a period
             * or has any two consecutive periods.
             */
            no_unsafe_periods: function(text) {

                // if the text has '.' as the first or last character then it's not valid
                if (text.charAt(0) === "." || text.charAt(text.length - 1) === ".") {
                    return false;
                }

                // if the texting contains '..' then it's not valid
                if (/\.\./.test(text) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates the local part of an email address: <u>local</u>@domain.tld<br />
                see: <a href="http://en.wikipedia.org/wiki/E-mail_address#RFC_specification">RFC spec</a>.
                @note Preserved for legacy x3 support. Use the new email_username, ftp_username and
                webmail_username in all new code.
                @method local_part_email
                @param {string} str The local part of an email address.
                @param {spec} str (optional) either "cpanel" or "rfc", defaults to rfc
                @param {Boolean} charCheckOnly (optional) When true, the validator ony checks the character regex
                @return {boolean} returns true if <code>str</code> fits the RFC spec
            */
            local_part_email: function(str, spec, charCheckOnly) {
                return _validate_local_part(str, spec, charCheckOnly);
            },

            /**
                Validates the local part of an email address: <u>local</u>@domain.tld<br />
                see: <a href="http://en.wikipedia.org/wiki/E-mail_address#RFC_specification">RFC spec</a>.
                @method email_username
                @param {string} str The local part of an email address.
                @param {spec} str (optional) either "cpanel" or "rfc", defaults to rfc
                @param  {Boolean} charCheckOnly (optional) When true, the validator ony checks the character regex
                @return {boolean} returns true if <code>str</code> fits the RFC spec
            */
            email_username: function(str, spec, charCheckOnly) {
                return _validate_local_part(str, "cpanel", charCheckOnly);
            },

            /**
                Validates a webmail username.
                @method ftp_username
                @param {string} str The username requested.
                @return {boolean} returns true if <code>str</code> fits the requested spec, false otherwise
            */
            ftp_username: function(str) {
                return _validate_local_part(str, "cpanel");
            },

            /**
                Validates a webdisk username.
                @method webdisk_username
                @param {string} str The username requested.
                @return {boolean} returns true if <code>str</code> fits the requested spec, false otherwise
            */
            webdisk_username: function(str) {
                return _validate_local_part(str, "cpanel");
            },

            /**
                This function validates a hostname: http://<u>cpanel.net</u>
                @method host
                @param {string} str A hostname.
                @return {boolean} returns true if <code>str</code> is a valid hostname
            */
            host: function(str) {
                var chunks = str.split(".");
                if (chunks.length < 2) {
                    return false;
                }

                for (var i = 0; i < chunks.length - 1; i++) {
                    if (!CPANEL.validate.domain(chunks[i])) {
                        return false;
                    }
                }

                // last chunk must be a tld
                if (!CPANEL.validate.tld("." + chunks[chunks.length - 1])) {
                    return false;
                }

                return true;
            },

            /**
                This function validates an email address to RFC spec: <u>local@domain.tld</u>
                @method email
                @param {string} str An email address.
                @return {boolean} returns true if <code>str</code> is a valid email address
            */
            email: function(str) {

                // split on the @ symbol
                var groups = str.split("@");

                // must be split into two at this point
                if (groups.length !== 2) {
                    return false;
                }

                // validate the local part
                if (!_validate_local_part(groups[0], "rfc")) {
                    return false;
                }

                // validate the rest
                return CPANEL.validate.fqdn(groups[1]);
            },

            /**
                This function validates an email address to cPanel spec: <u>local@domain.tld</u>
                @method cpanel_email
                @param {string} str An email address.
                @return {boolean} returns true if <code>str</code> is a valid cpanel email address
            */
            cpanel_email: function(str) {

                // split on the @ symbol
                var groups = str.split("@");

                // must be split into two at this point
                if (groups.length !== 2) {
                    return false;
                }

                // validate the local part
                if (!_validate_local_part(groups[0], "cpanel")) {
                    return false;
                }

                // validate the rest
                return CPANEL.validate.fqdn(groups[1]);
            },

            /**
            This function validates an image extension: 'gif', 'jpg', 'jpeg', 'png'
            @method external_check_image_extension
            @param {string} str An image extension.
            @return {boolean} returns true if <code>str</code> is a valid image extension
            */
            external_check_image_extension: function(str, fname) {

                // empty string is ok
                if (str === "") {
                    return true;
                }

                // make sure there is an extension
                if (!(/[^.]\.[^.]+$/.test(str))) {
                    return false;
                }

                var given_extension = str.split(".").pop();

                var allowed_extensions = ["gif", "jpg", "jpeg", "png"];

                return (allowed_extensions.indexOf(given_extension.toLowerCase()) !== -1);
            },

            /**
                This function validates a URL: <u>http://cpanel.net</u><br />
                The URL must include <code>http://</code> or <code>https://</code> at the beginning.
                @method url
                @param {string} str a URL
                @return {boolean} returns true if <code>str</code> is a valid URL
            */
            url: function(str) {

                // must contain 'http://' or 'https://' at the start
                if (str.substring(0, 7) !== "http://" && str.substring(0, 8) !== "https://") {
                    return false;
                }

                // grab the domain and tlds
                var front_slashes = str.search(/:\/\//);
                if (front_slashes === -1) {
                    return false;
                }
                str = str.substring(front_slashes + 3);

                // see if there is something after the last tld (path)
                var back_slash = str.search(/\//);
                if (back_slash === -1) {
                    back_slash = str.length;
                }
                var domain_and_tld = str.substring(0, back_slash);

                return CPANEL.validate.fqdn(domain_and_tld);
            },

            fqdn: function(str) {

                // check the domain and tlds
                var groups = str.split(".");

                // must have at least one domain and tld
                if (groups.length < 2) {
                    return false;
                }

                // check each group
                for (var i = 0; i < groups.length; i++) {

                    // the first entry must be a domain
                    if (i === 0) {
                        if (!CPANEL.validate.domain(groups[i])) {
                            return false;
                        }
                    }

                    // the last entry must be a tld
                    if (i === groups.length - 1) {
                        if (!CPANEL.validate.tld("." + groups[i])) {
                            return false;
                        }
                    }

                    // everything else in between must be either a domain or a tld
                    if (!CPANEL.validate.tld("." + groups[i]) && !CPANEL.validate.domain(groups[i])) {
                        return false;
                    }
                }

                return true;
            },

            /**
                Validates a top level domain (TLD): .com, .net, .org, .co.uk, etc<br />
                This function does not check against a list of TLDs.  Instead it makes sure that the TLD is formatted correctly.<br />
                TLD must begin with a period (.)
                @method tld
                @param {string} str a TLD
                @return {boolean} returns true if <code>str</code> is a valid TLD
            */
            tld: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9-.]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // string must have '.' as a first character and neither '.' nor '-' as a last character
                if (str.charAt(0) !== "." || /[.-]$/.test(str)) {
                    return false;
                }

                // string cannot contain any of: ..  .-  -.  ---
                if (/\.[.-]/.test(str) || /-\./.test(str) || /---/.test(str)) {
                    return false;
                }

                return true;
            },

            /**
                Validates a domain name: http://<u>cpanel</u>.net
                @method domain
                @param {string} str a domain
                @return {boolean} returns true if <code>str</code> is a valid domain
            */
            domain: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^_a-zA-Z0-9-]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // We're allowing underscores but only as the first character
                if (/_/.test(str.substr(1))) {
                    return false;
                }

                // string cannot have '-' as a first or last character
                if (str.charAt(0) === "-" || str.charAt(str.length - 1) === "-") {
                    return false;
                }

                // domain name cannot be longer than 63 characters
                if (str.length === 0 || str.length > 63) {
                    return false;
                }

                return true;
            },

            /**
                Validates a subdomain: http://<u>foo</u>.cpanel.net
                @method subdomain
                @param {string} str a subdomain
                @return {boolean} returns true if <code>str</code> is a valid subdomain
            */
            subdomain: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^_a-zA-Z0-9-.]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // We're allowing underscores but only as the first character
                if (/_/.test(str.substr(1))) {
                    return false;
                }

                // last character must be alphanumeric
                if (!CPANEL.validate.alphanumeric(str.charAt(str.length - 1))) {
                    return false;
                }

                // subdomain cannot be longer than 63 characters
                if (str.length === 0 || str.length > 63) {
                    return false;
                }

                // string cannot contain '..'
                pattern = new RegExp(/\.\./);
                if (pattern.test(str) === true) {
                    return false;
                }

                return true;
            },

            /**
                Validates an ISO 3166-1 alpha-2 country code: US, GB, CA, DE...
                @method country_code
                @param {string} str a country code in upper case
                @return {boolean} returns true if <code>str</code> is a valid country code
            */
            country_code: function(str) {
                var codes = ["AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR",
                    "AS", "AT", "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF",
                    "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS",
                    "BT", "BV", "BW", "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH",
                    "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX",
                    "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG",
                    "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO", "FR", "GA",
                    "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP",
                    "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HM", "HN", "HR",
                    "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS",
                    "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN",
                    "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR",
                    "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG",
                    "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT",
                    "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG",
                    "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF",
                    "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY",
                    "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE",
                    "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS",
                    "ST", "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ",
                    "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA",
                    "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI", "VN",
                    "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW",
                ];

                return codes.indexOf(str) > -1;
            },

            /**
                Validates alpha characters: a-z A-Z
                @method alpha
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alpha characters
            */
            alpha: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates alphanumeric characters: a-z A-Z 0-9
                @method alphanumeric
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alphanumeric characters
            */
            alphanumeric: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates alphanumeric characters: a-z A-Z 0-9, underscore (_) and hyphen (-)
                @method sql_alphanumeric
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alphanumeric characters and or underscore
            */
            sql_alphanumeric: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string cannot contain a trailing underscore
                if (/_$/.test(str)) {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9_-]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a string is a minimum length.
                @method min_length
                @param {string} str the string to check
                @param {integer} length the minimum length of the string
                @return {boolean} returns true if <code>str</code> is longer than or equal to <code>length</code>
            */
            min_length: function(str, length) {
                if (str.length >= length) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a string is not longer than a maximum length.
                @method max_length
                @param {string} str the string to check
                @param {integer} length the maximum length of the string
                @return {boolean} returns true if <code>str</code> is shorter than or equal to <code>length</code>
            */
            max_length: function(str, length) {
                if (str.length <= length) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a string is not shorter the the minimum length and not longer than a maximum length.
                @method length_check
                @param {string} str the string to check
                @param {integer} minLength the minimum length of the string
                @param {integer} maxLength the maximum length of the string
                @return {boolean} returns true if the length of <code>str</code> between <code>minLength</code> and <code>maxLength</code>.
            */
            length_check: function(str, minLength, maxLength) {
                var len = str.length;
                if (len >= minLength && len <= maxLength) {
                    return true;
                }
                return false;
            },

            /**
                Validates that two fields have the same value (useful for password input).
                @method equals
                @param {DOM element} el1 The first element.  Should be of type "text"
                @param {DOM element} el2 The second element.  Should be of type "text"
                @return {boolean} returns true if el1.value equals el2.value
            */
            equals: function(el1, el2) {
                el1 = YAHOO.util.Dom.get(el1);
                el2 = YAHOO.util.Dom.get(el2);
                if (el1.value == el2.value) {
                    return true;
                }
                return false;
            },

            /**
                Validates that two fields do not have the same value (useful for password input).
                @method equals
                @param {DOM element} el1 The first element.  Should be of type "text"
                @param {DOM element} el2 The second element.  Should be of type "text"
                @return {boolean} returns true if el1.value equals el2.value
            */
            not_equals: function(el1, el2) {
                el1 = YAHOO.util.Dom.get(el1);
                el2 = YAHOO.util.Dom.get(el2);
                if (el1.value == el2.value) {
                    return false;
                }
                return true;
            },

            /**
                Validates anything.<br />
                Useful when you want to accept any input from the user, but still give them the same visual feedback they get from input fields that actually get validated.
                @method anything
                @return {boolean} returns true
            */
            anything: function() {
                return true;
            },

            /**
                Validates a field only if it has a value.
                @method if_not_empty
                @param {string | DOM element} value If a DOM element is passed in it should be an input of type="text".  Its value will be grabbed with YAHOO.util.Dom.get(<code>value</code>).value
                @param {function} func The function to check the value against.
                @return {boolean} returns the value of <code>func(value)</code> or true if <code>value</code> is empty
            */
            if_not_empty: function(value, func) {

                // if value is not a string, assume it's an element and grab its value
                if (typeof (value) !== "string") {
                    value = YAHOO.util.Dom.get(value).value;
                }

                if (value !== "") {
                    return func(value);
                }
                return true;
            },

            /**
                Validates that a field contains a positive integer.
                @method positive_integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is a positive integer
            */
            positive_integer: function(value) {

                // convert value to a string
                value = value + "";

                if (value === "") {
                    return false;
                }
                var pattern = new RegExp("[^0-9]");
                if (pattern.test(value) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains a negative integer.
                @method negative_integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is a negative integer
            */
            negative_integer: function(value) {

                // convert value to a string
                value = value + "";

                // first character must a minus sign
                if (value.charAt(0) !== "-") {
                    return false;
                }

                // get the rest of the string
                value = value.substr(1);

                var pattern = new RegExp("[^0-9]");
                if (pattern.test(value) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains a integer.
                @method integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is an integer
            */
            integer: function(value) {
                if (CPANEL.validate.negative_integer(value) ||
                    CPANEL.validate.positive_integer(value)) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a field contains an integer less than a <code>value</code>
                @method max_value
                @param {integer} value the value to check
                @param {integer} max the maximum value
                @returns {boolean} returns true if <code>value</code> is an integer less than <code>max</code>
            */
            max_value: function(value, max) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }

                // convert types to integers for the test
                value = parseInt(value, 10);
                max = parseInt(max, 10);

                if (value > max) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains an integer greater than a <code>value</code>
                @method min_value
                @param {integer} value the value to check
                @param {integer} min the minimum value
                @returns {boolean} returns true if <code>value</code> is an integer greater than <code>max</code>
            */
            min_value: function(value, min) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                min = parseInt(min, 10);

                if (value < min) {
                    return false;
                }
                return true;
            },

            less_than: function(value, less_than) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                less_than = parseInt(less_than, 10);

                if (value < less_than) {
                    return true;
                }
                return false;
            },

            greater_than: function(value, greater_than) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                greater_than = parseInt(greater_than, 10);

                if (value > greater_than) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a field does not contain a set of characters.
                @method no_chars
                @param {string} str The string to check against.
                @param {char | Array} chars Either a single character or an array of characters to check against.
                @return {boolean} returns true if none of the characters in <code>chars</code> exist in <code>str</code>.
            */
            no_chars: function(str, chars) {

                // convert chars into an array if it is not
                if (typeof (chars) === "string") {
                    var chars2 = chars.split("");
                    chars = chars2;
                }

                for (var i = 0; i < chars.length; i++) {
                    if (str.indexOf(chars[i]) !== -1) {
                        return false;
                    }
                }

                return true;
            },

            not_string: function(str, notstr) {
                if (str == notstr) {
                    return false;
                }
                return true;
            },

            // directory paths cannot contain the following characters: \ ? % * : | " < >
            dir_path: function(str) {

                // string cannot contain these characters: \ ? % * : | " < >
                var chars = "\\?%*:|\"<>";
                return CPANEL.validate.no_chars(str, chars);
            },

            // user web directories cannot be one of the cpanel reserved directories
            reserved_directory: function(str) {

                // Prevent weird no-op directory-spec to avoid this check
                if (str.indexOf("/") === 0) {
                    str = str.substr(1);
                }
                while (str.indexOf("./") === 0) {
                    str = str.substr(2);
                }

                var DisallowedDirectories = [ "",
                    ".cpanel", ".htpasswds", ".spamassassin", ".ssh", ".trash",
                    "cgi-bin", "etc", "logs", "mail", "perl5", "ssl", "tmp", "var" ];
                if ( DisallowedDirectories.indexOf(str) > -1) {
                    return false;
                }
                return true;
            },

            // quotas must be either a number or "unlimited"
            quota: function(str) {
                if (!CPANEL.validate.positive_integer(str) && (str !== LOCALE.maketext("unlimited"))) {
                    return false;
                }
                return true;
            },

            // MIME type
            mime: function(str) {

                // cannot have spaces
                if (!CPANEL.validate.no_chars(str, " ")) {
                    return false;
                }

                // must contain only one forward slash
                var names = str.split("/");
                if (names.length !== 2) {
                    return false;
                }

                // use same rule as Cpanel::Mime::_is_valid_mime_type
                var pattern = /^[a-zA-Z0-9!#$&.+^_-]+$/;
                for (var i = 0; i < names.length; i++) {
                    if (!names[i] || names[i].length > 127 || !pattern.test(names[i])) {
                        return false;
                    }
                }

                return true;
            },

            // MIME extension
            mime_extension: function(str) {

                // must be a minimum of one alpha-numeric character
                var pattern = new RegExp(/\w/g);
                if (pattern.test(str) === false) {
                    return false;
                }

                // cannot contain special filename characters
                return CPANEL.validate.no_chars(str, "/&?\\");
            },

            apache_handler: function(str) {

                // cannot have spaces
                if (!CPANEL.validate.no_chars(str, " ")) {
                    return false;
                }

                // forward slash /
                var hyphen1 = str.indexOf("-");
                var hyphen2 = str.lastIndexOf("-");
                if (hyphen1 === -1) {
                    return false; // must contain at least one hyphen
                }
                if (hyphen1 === 0 || hyphen2 === (str.length - 1)) {
                    return false; // hyphen cannot be first or last character
                }

                return true;
            },

            // validates an IP address
            ip: function(str) {
                var chunks = str.split(".");
                if (chunks.length !== 4) {
                    return false;
                }

                for (var i = 0; i < chunks.length; i++) {
                    if (!CPANEL.validate.positive_integer(chunks[i])) {
                        return false;
                    }
                    if (chunks[i] > 255) {
                        return false;
                    }
                }

                return true;
            },

            // A port of the logic in Cpanel::Validate::IP
            ipv6: function(str) {
                if (!str) {
                    return false;
                }

                return CPANEL.inet6.isValid(str);
            },

            // returns false if they enter a local IP address, 127.0.0.1, 0.0.0.0
            no_local_ips: function(str) {
                return !(str === "127.0.0.1" || str === "0.0.0.0");
            },

            // validates a filename
            filename: function(str) {
                if (str.indexOf("/") !== -1) {
                    return false; // cannot be a directory path (forward slash)
                }

                if (!CPANEL.validate.dir_path(str)) {
                    return false;
                }
                return true;
            },

            // str==source, allowed is an array of possible endings (returns true on match), case insensitive
            end_of_string: function(str, allowed) {

                // convert "allowed" to an array if it's not otherwise so
                if (!YAHOO.lang.isArray(allowed)) {
                    allowed = [allowed];
                }

                // Compare each element of allowed against str
                for (var i = 0;
                    (i < allowed.length); i++) {
                    if (str.substr(str.length - allowed[i].length).toLowerCase() === allowed[i].toLowerCase()) {
                        return true;
                    }
                }
                return false;
            },

            // must end and begin with an alphanumeric character, many logins require this
            alphanumeric_bookends: function(str) {
                if (str === "") {
                    return true;
                }

                if (!CPANEL.validate.alphanumeric(str.charAt(0))) {
                    return false;
                }

                if (!CPANEL.validate.alphanumeric(str.charAt(str.length - 1))) {
                    return false;
                }

                return true;
            },

            zone_name: function(str) {
                if (str === "") {
                    return false;
                }

                // cut off the trailing period if it's there
                if (str.charAt(str.length - 1) === ".") {
                    str = str.substr(0, str.length - 1);
                }

                var chunks = str.split(".");
                if (chunks.length < 1) {
                    return false;
                }

                for (var i = 0; i < chunks.length; i++) {
                    if ((!CPANEL.validate.domain(chunks[i])) && (chunks[i] !== "*")) {
                        return false;
                    }
                }

                return true;
            },

            // Verify the case-insensitive value is not present in str
            not_present: function(str, value) {
                return !CPANEL.validate.present(str, value);
            },

            // Verify the case-insensitive value is present in str
            present: function(str, value) {

                // Convert everything to lower case for case insensitivity.
                var lower_str = str.toLowerCase();
                var lower_value = value.toLowerCase();
                if (lower_str.indexOf(lower_value) >= 0) {
                    return true;
                }
                return false;
            },

            // Verify that the string is not the domain or one of its subdomains.
            not_in_domain: function(str, domain) {
                return !CPANEL.validate.in_domain(str, domain);
            },

            // Verify that the string is the domain or one of its subdomains.
            in_domain: function(str, domain) {

                // Convert everything to lower case for case insensitivity.
                var lower_str = str.toLowerCase();
                var lower_domain = domain.toLowerCase();
                var domain_pat = lower_domain.replace(/\./g, "\\.");
                if (lower_str === lower_domain) {
                    return true;
                }
                var subdomain_pat = new RegExp("\\." + domain_pat + "$");
                if (subdomain_pat.test(lower_str)) {
                    return true;
                }

                return false;
            },
        };

        CPANEL.validate.validator.prototype = {};
    }
})();

//--- end /usr/local/cpanel/base/cjt/validate.js ---

//--- start /usr/local/cpanel/base/cjt/validation_definitions.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/*
Validation Atoms (the lowest level of validation structure)
> contains a boolean function in one of the following formats: valid_chars, invalid_chars, valid, invalid, min_length, max_length, less_than, greater_than
> each method is accompanied with a message (msg)
> messages can have some limited variable interpolation

valid_chars, invalid_chars
> character string
> can contain three optional ranges: a-z, A-Z, 0-9
> msg has 1 variable available to it: %invalid_chars%

valid_regexp
> regular expression
> should be very basic and easy to read
> must work in both Perl and JavaScript
> if the input string finds a match against the regular expression the function returns true
> if the regular expression finds a match against the input string --> return true
> if the regular expression does not find a match against the input string --> return false

invalid_regexp
> regular expression
> should be very basic and easy to read
> must work in both Perl and JavaScript
> msg has 1 variable available to it: %invalid%
> if the input string finds a match against the regular expression the function returns false

max_length, min_length
> integer
> compares against the length of the string
> msg has no variables available

less_than, greater_than
> integer
> treats the string as an number, returns false if the string is not a number
> msg has no variables available
*/

CPANEL.validation_definitions = {
    "IPV4_ADDRESS": [{
        "min_length": "1",
        "msg": "IP Address cannot be empty."
    }, {
        "valid_chars": ".0-9",
        "msg": "IP Address must contain only digits and periods."
    }, {
        "valid_regexp": "/^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$/",
        "msg": "IP Address not formatted correctly.  ie: 4.2.2.2, 192.168.1.100"
    }],

    "IPV4_ADDRESS_NO_LOCAL_IPS": [
        "IPV4_ADDRESS", {
            "invalid_regexp": "/(127\\.0\\.0\\.1)|(0\\.0\\.0\\.0)/",
            "msg": "IP Address cannot be local.  ie: 127.0.0.1, 0.0.0.0"
        }
    ],

    "LOCAL_EMAIL": [{
        "min_length": "1",
        "msg": "Email cannot be empty."
    }, {
        "max_length": "128",
        "msg": "Email cannot be longer than 128 characters."
    }, {
        "invalid_chars": " ",
        "msg": "Email cannot contain spaces."
    }, {
        "invalid_regexp": "/\\.\\./",
        "msg": "Email cannot contain two consecutive periods."
    }, {
        "invalid_regexp": "/^\\./",
        "msg": "Email cannot start with a period."
    }, {
        "invalid_regexp": "/\\.$/",
        "msg": "Email cannot end with a period. %invalid%"
    }],

    "LOCAL_EMAIL_CPANEL": [
        "LOCAL_EMAIL", {
            "valid_chars": ".a-zA-Z0-9!#$=?^_{}~-",
            "msg": "Email contains illegal characters: %invalid_chars%"
        }
    ],

    "LOCAL_EMAIL_RFC": [
        "LOCAL_EMAIL", {
            "valid_chars": ".a-zA-Z0-9!#$%&'*+/=?^_`{|}~-",
            "msg": "Email contains illegal characters: %invalid_chars%"
        }
    ],

    "FULL_EMAIL": [{
        "min_length": "1",
        "msg": "Email cannot be empty."
    }, {
        "invalid_chars": " ",
        "msg": "Email cannot contain spaces."
    }, {
        "": "",
        "msg": ""
    }],

    "FULL_EMAIL_CPANEL": [

    ],

    "FULL_EMAIL_RFC": [

    ],

    "DOMAIN": [

    ],

    "SUBDOMAIN": [{
        "min_length": "1",
        "msg": "Subdomain cannot be empty."
    }, {
        "max_length": "63",
        "msg": "Subdomain cannot be longer than 63 characters."
    }, {
        "invalid_chars": " ",
        "msg": "Subdomain cannot contain spaces."
    }, {
        "invalid_regexp": "\\.\\.",
        "msg": "Subdomain cannot contain two consecutive periods."
    }, {
        "valid_chars": "a-zA-Z0-9_-.",
        "msg": "Subdomain contains invalid characters: %invalid_chars%"
    }],

    "FQDN": [

    ],

    "TLD": [

    ],

    "FTP_USERNAME": [

    ],

    "MYSQL_DB_NAME": [

    ],

    "MYSQL_USERNAME": [

    ],

    "POSTGRES_DB_NAME": [

    ],

    "POSTGRES_USERNAME": [

    ]
};

//--- end /usr/local/cpanel/base/cjt/validation_definitions.js ---

//--- start /usr/local/cpanel/base/cjt/widgets.js ---
/*
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {

    // TODO: This stuff should go in a markup island; however, there isn't currently
    // a template that CJT can always rely on being there, so for now this is going
    // into JS directly.
    var close_x = (YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9)) ?
        "X" :

        // NOTE: The final <rect> is so that the entire <svg> surface is a single
        // target for DOM clicks. Otherwise, the pixel-shift that CSS does with this
        // will make the mousedown and mouseup have different targets, which
        // prevents "click" from being triggered.
        '<svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg"><line stroke="currentColor" stroke-width="1.5" stroke-linecap="round" x1="35%" y1="35%" x2="65%" y2="65%" /><line stroke="currentColor" stroke-width="1.5" stroke-linecap="round" x1="35%" y1="65%" x2="65%" y2="35%" /><rect width="100%" height="100%" style="fill:transparent;opacity:1.0" /></svg>';

    var closeButton = YAHOO.lang.substitute(
        "<a class='cjt-dynamic-pagenotice-close-button' href='javascript:void(0)' title=\"{title}\">{close_x}</a>", {
            title: LOCALE.maketext("Click to close."),
            close_x: close_x
        }
    );

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL == "undefined" || !CPANEL) {
        alert("You must include the CPANEL global object before including widgets.js!");
    } else {

        /**
        The widgets module contains widget objects used in cPanel.
        @module widgets
*/

        /**
        The widgets class contains widget objects used in cPanel.
        @class widgets
        @namespace CPANEL
        @extends CPANEL
*/
        CPANEL.widgets = {

            // LEGACY USE ONLY.
            Text_Input_Placeholder: function(context_el, text, before_show) {
                context_el = DOM.get(context_el);

                var id = context_el.id;
                if (id) {
                    id += "_cjt-text-input-placeholder";
                } else {
                    id = DOM.generateId();
                }

                // adjust the overlay for the context element border and padding
                var region = CPANEL.dom.get_inner_region(context_el);
                var xy_offset = [
                    region.padding.left + region.border.left,
                    region.padding.top + region.border.top
                ];

                var opts = {
                    context: [context_el, "tl", "tl", ["beforeShow", "windowResize"], xy_offset],
                    width: region.width + "px",
                    height: region.height + "px",
                    zIndex: parseInt(DOM.getStyle(context_el, "z-index"), 10) + 1,
                    visible: false
                };

                arguments.callee.superclass.constructor.call(this, id, opts);


                var render_parent = context_el.parentNode;
                if (render_parent.nodeName.toLowerCase() === "label") {
                    render_parent = render_parent.parentNode;
                }

                this.render(render_parent);

                var overlay = this;
                this.element.onclick = function() {
                    overlay.hide();
                    context_el.focus();
                };

                DOM.addClass(this.element, "cjt-text-input-placeholder");

                var helper_text = text || "";
                this.setBody(helper_text);

                YAHOO.util.Event.addListener(context_el, "focus", function() {
                    overlay.hide();
                });
                YAHOO.util.Event.addListener(context_el, "blur", function() {
                    if (!this.value.trim()) {
                        overlay.show();
                    }
                });

                if (before_show) {
                    before_show.apply(this);
                }

                if (!context_el.value.trim()) {
                    this.show();
                }
            },

            // show a progress bar
            progress_bar: function(el, percentage, text, options) {

                // just a legacy thing so I don't have to backmerge a change for 11.25
                if (options == '{"inverse_colors":"true"}') {
                    options = {
                        inverse_colors: true
                    };
                }

                if (!options) {
                    options = {};
                }
                if (!options.text_style) {
                    options.text_style = "";
                }
                if (!options.inverse_colors) {
                    options.inverse_colors = false;
                }
                if (!options.one_color) {
                    options.one_color = false;
                }
                if (!options.return_html) {
                    options.return_html = false;
                }

                // clean the percentage
                percentage = parseInt(percentage, 10);
                if (percentage < 0) {
                    percentage = 0;
                }
                if (percentage > 100) {
                    percentage = 100;
                }

                // get the element
                if (options.return_html === false) {
                    el = YAHOO.util.Dom.get(el);
                }

                // set the color of the bar
                var color;
                if (percentage >= 0) {
                    color = "#FF0000";
                } // red
                if (percentage >= 20) {
                    color = "#FF9837";
                } // orange
                if (percentage >= 40) {
                    color = "#F1FF4D";
                } // yellow
                if (percentage >= 60) {
                    color = "#C5FF00";
                } // chartreuse
                if (percentage >= 80) {
                    color = "#8FFF00";
                } // lt green

                if (options.inverse_colors) {
                    if (percentage >= 0) {
                        color = "#8FFF00";
                    } // lt green
                    if (percentage >= 20) {
                        color = "#C5FF00";
                    } // chartreuse
                    if (percentage >= 40) {
                        color = "#F1FF4D";
                    } // yellow
                    if (percentage >= 60) {
                        color = "#FF9837";
                    } // orange
                    if (percentage >= 80) {
                        color = "#FF0000";
                    } // red
                }

                if (options.one_color) {
                    color = options.one_color;
                }

                var height = "100%";

                // BROWSER-SPECIFIC CODE: manually get the height from the parent element for ie6
                if (YAHOO.env.ua.ie == 6 && options.return_html === false) {
                    var div_region = YAHOO.util.Region.getRegion(el);
                    height = div_region.height + "px";
                }

                var html;

                // container div with relative positioning, height/width set to 100% to fit the container element
                html = '<div class="cpanel_widget_progress_bar" title="' + percentage + '%" style="position: relative; width: 100%; height: ' + height + '; padding: 0px; margin: 0px; border: 0px">';

                // text div fits the width and height of the container div and has it's text vertically centered; has an opaque background and z-index of 1 to put it above the color bar div
                if (text) {
                    html += '<div style="position: absolute; left: 0px; width: 100%; height: ' + height + '; padding: 0px; margin: 0px; border: 0px; z-index: 1; background-image: url(\'/cPanel_magic_revision_0/cjt/images/1px_transparent.gif\')">';
                    html += '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px; border: 0px">';
                    html += '<tr><td valign="middle" style="padding: 0px; margin: 0px; border: 0px;">'; // use a table to vertically center for greatest compatability
                    html += '<div style="width: 100%; ' + options.text_style + '">' + text + "</div>";
                    html += "</td></tr></table>";
                    html += "</div>";
                }

                // color bar div fits the width and height of the container div and width changes depending on the strength of the password
                if (percentage > 0) {
                    html += '<div style="position: absolute; left: 0px; top: 0px; width: ' + percentage + "%; height: " + height + "; background-color: " + color + '; padding: 0px; margin: 0px; border: 0px"></div>';
                }

                // close the container div
                html += "</div>";

                // save the percent information in a hidden div
                if (options.return_html === false) {
                    html += '<div class="cpanel_widget_progress_bar_percent" style="display: none">' + percentage + "</div>";
                }

                if (options.return_html === true) {
                    return html;
                }

                el.innerHTML = html;
            },

            build_progress_bar: function(percentage, text, options) {


            },

            // variable used to hold the status box overlay widget
            status_box: null,

            // variable used to hold the status box overlay's timeout
            status_box_timeout: null,

            status: function(message, class_name) {

                // if the status bar is currently being displayed clear the previous timeout
                clearTimeout(this.status_box_timeout);

                var options = {
                    zIndex: 1000,
                    visible: true,
                    effect: {
                        effect: YAHOO.widget.ContainerEffect.FADE,
                        duration: 0.25
                    }
                };
                this.status_box = new YAHOO.widget.Overlay("cpanel_status_widget", options);
                this.status_box.setBody('<span class="cpanel_status_widget_message">' + message + "</span>");

                var footer = '<br /><div style="width: 100%; text-align: right; font-size: 10px">';
                footer += LOCALE.maketext("Click to close.") + ' [<span id="cpanel_status_widget_countdown">10</span>]';
                footer += "</div>";
                this.status_box.setFooter(footer);
                this.status_box.render(document.body);

                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_success");
                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_error");
                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_warning");
                if (class_name) {
                    YAHOO.util.Dom.addClass("cpanel_status_widget", "cpanel_status_" + class_name);
                } else {
                    YAHOO.util.Dom.addClass("cpanel_status_widget", "cpanel_status_success");
                }

                var hide_me = function() {
                    CPANEL.widgets.status_box.hide();
                    clearTimeout(CPANEL.widgets.status_box_timeout);
                };

                YAHOO.util.Event.on("cpanel_status_widget", "click", hide_me);

                var second_decrease = function() {
                    var seconds_el = YAHOO.util.Dom.get("cpanel_status_widget_countdown");
                    if (seconds_el) {
                        var seconds = parseInt(seconds_el.innerHTML, 10);

                        // close the window when the countdown is finished
                        if (seconds === 0) {
                            hide_me();
                        } else { // else decrease the counter and set a new timeout
                            seconds_el.innerHTML = seconds - 1;
                            CPANEL.widgets.status_box_timeout = setTimeout(second_decrease, 1000);
                        }
                    }
                };

                // initialize the first timeout
                this.status_box_timeout = setTimeout(second_decrease, 1000);
            },

            // status_bar widget
            /*
            var status_bar_options = {
            duration : integer,
            callbackFunc : function literal,
            hideCountdown : true,
            noCountdown : true,
            rawHTML : HTML string
            }
            */
            status_bar: function(el, style, title, message, options) {
                var duration = 10;
                if (style == "error") {
                    duration = 0;
                }

                // options
                var callback_func = function() {};
                var hide_countdown = false;
                var countdown = true;
                if (duration === 0) {
                    countdown = false;
                }
                var raw_html = false;
                if (options) {
                    if (options.duration) {
                        duration = options.duration;
                    }
                    if (options.callbackFunc) {
                        if (typeof (options.callbackFunc) == "function") {
                            callback_func = options.callbackFunc;
                        }
                    }
                    if (options.hideCountdown) {
                        hide_countdown = true;
                    }
                    if (options.rawHTML) {
                        raw_html = options.rawHTML;
                    }
                    if (options.noCountdown) {
                        countdown = false;
                    }
                }

                el = YAHOO.util.Dom.get(el);
                if (!el) {
                    alert("Error in CPANEL.widgets.status_bar: '" + el + "' does not exist in the DOM.");
                    return;
                }

                var hide_bar = function() {
                    CPANEL.animate.slide_up(el, function() {
                        el.innerHTML = "";
                        callback_func();
                        CPANEL.align_panels_event.fire();
                    });
                };

                // set the style class
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_success");
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_error");
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_warning");
                YAHOO.util.Dom.addClass(el, "cjt_status_bar_" + style);

                var status = "";
                if (raw_html === false) {
                    status = CPANEL.icons.success;
                    if (style == "error") {
                        status = CPANEL.icons.error;
                    }
                    if (style == "warning") {
                        status = CPANEL.icons.warning;
                    }

                    status += " <strong>" + title + "</strong>";
                    if (message) {
                        if (message !== "") {
                            status += '<div style="height: 5px"></div>';
                            status += CPANEL.util.convert_breaklines(message);
                        }
                    }
                } else {
                    status = raw_html;
                }

                var countdown_div = "";
                if (countdown === true) {
                    countdown_div = '<div class="cjt_status_bar_countdown"';
                    if (hide_countdown === true) {
                        countdown_div += ' style="display: none"';
                    }

                    var countdown_inner = LOCALE.maketext("Click to close.") + " {durationspan}"; // See first post in rt 62397, in the meantime the text will be localized
                    countdown_inner = countdown_inner.replace("{durationspan}", '[<span id="' + el.id + '_countdown">' + duration + "</span>]");

                    countdown_div += ">" + countdown_inner + "</div>";
                } else {
                    countdown_div = '<div class="cjt_status_bar_countdown">' + LOCALE.maketext("Click to close.") + "</div>";
                }

                el.innerHTML = status + countdown_div;

                CPANEL.animate.slide_down(el, function() {

                    // give the status bar element "hasLayout" property in IE
                    if (YAHOO.env.ua.ie > 5) {
                        YAHOO.util.Dom.setStyle(el, "zoom", "1");
                    }
                    if (countdown === true) {
                        CPANEL.util.countdown(el.id + "_countdown", hide_bar);
                    }
                    CPANEL.align_panels_event.fire();
                });

                YAHOO.util.Event.on(el, "click", hide_bar);
            },

            collapsible_header: function(header_el, div_el, before_show, after_show, before_hide, after_hide) {

                // grab the DOM elements
                header_el = YAHOO.util.Dom.get(header_el);
                div_el = YAHOO.util.Dom.get(div_el);

                if (!header_el) {
                    alert("Error in CPANEL.widgets.collapsable_header: header_el '" + header_el + "' does not exist in the DOM.");
                    return;
                }
                if (!div_el) {
                    alert("Error in CPANEL.widgets.collapsable_header: div_el '" + div_el + "' does not exist in the DOM.");
                    return;
                }

                // set up the functions if they are not defined
                if (!before_show || typeof (before_show) != "function") {
                    before_show = function() {};
                }
                if (!after_show || typeof (after_show) != "function") {
                    after_show = function() {};
                }
                if (!before_hide || typeof (before_hide) != "function") {
                    before_hide = function() {};
                }
                if (!after_hide || typeof (after_hide) != "function") {
                    after_hide = function() {};
                }

                // toggle function
                var toggle_function = function() {

                    // if the display is none, expand the div
                    if (YAHOO.util.Dom.getStyle(div_el, "display") == "none") {
                        before_show();
                        YAHOO.util.Dom.replaceClass(header_el, "cjt_header_collapsed", "cjt_header_expanded");
                        CPANEL.animate.slide_down(div_el, function() {
                            after_show();
                            CPANEL.align_panels_event.fire();
                        });
                    } else { // else hide it
                        before_hide();
                        CPANEL.animate.slide_up(div_el, function() {
                            after_hide();
                            YAHOO.util.Dom.replaceClass(header_el, "cjt_header_expanded", "cjt_header_collapsed");
                            CPANEL.align_panels_event.fire();
                        });
                    }
                };

                // add the event handler
                YAHOO.util.Event.on(header_el, "click", toggle_function);
            },

            /**
            The Dialog class contains objects and static helpers for Dialogs used in cPanel.
            @class Dialog
            @namespace CPANEL.widgets
            */
            Dialog: function() {}
        }; // end widgets object

        // ----------------------------------------------
        // Static extension to the widgets
        // ----------------------------------------------

        /**
         * Default dialog header template used if the header template is missing
         * @class  CPANEL.widgets.Dialog
         * @static
         * @property dialog_header_template
         * @type [string] the header template. */
        CPANEL.widgets.Dialog.dialog_header_template = "<div class='lt'></div><span>{header}</span><div class='rt'></div>";

        /**
         * Dialog header template match expression used to determin if the template if correctly formed.
         * @class  CPANEL.widgets.Dialog
         * @static
         * @property dialog_header_rule
         * @type [string] the header template match rule. */
        CPANEL.widgets.Dialog.dialog_header_rule = /<.*class='lt'.*\/>|<.*class='rt'.*\/>/gi;

        /**
         * Apply the default template to the dialog header if its missing
         * @class  CPANEL.widgets.Dialog
         * @static
         * @method applyDialogHeader
         * @param [string] header Current contents of the header. */
        CPANEL.widgets.Dialog.applyDialogHeader = function applyDialogHeader(header) {
            var CwD = CPANEL.widgets.Dialog;
            if (!header.match(CwD.dialog_header_rule)) {
                header = YAHOO.lang.substitute(CwD.dialog_header_template, {
                    "header": header
                });
            }
            return header;
        };


        YAHOO.lang.extend(CPANEL.widgets.Text_Input_Placeholder, YAHOO.widget.Overlay);

        var _is_ie6_or_7 = YAHOO.env.ua.ie && (YAHOO.env.ua.ie <= 7);
        if (_is_ie6_or_7) {
            var ie_shell_prototype; // lazy-load this value
            CPANEL.widgets.Text_Input_Placeholder.prototype.setBody = function(content) {
                if (content.nodeName) {
                    if (!ie_shell_prototype) {
                        ie_shell_prototype = document.createElement("div");
                        ie_shell_prototype.className = "cjt-ie-shell";
                    }
                    var ie_shell = ie_shell_prototype.cloneNode(false);
                    ie_shell.appendChild(content);
                } else {
                    content = "<div class=\"cjt-ie-shell\">" + content + "</div>";
                }

                return this.constructor.superclass.setBody.call(this, content);
            };
        }

        // -------------------------------------------------------------------------------------
        // Common notice functionality. This object contains many options for rendering notices
        //  into the user interface.
        //
        // If visible when rendered:
        //   If DOMReady, then slide down; otherwise, just be visible.
        //
        // @class Notice
        // @extends YAHOO.widget.Module
        // @param id {String} optional id of the content to show.
        // @param opts {Hash} first or second argument depending on if @id is passed.
        //  content   {String} HTML content of the notice
        //  level     {String} one of "success", "info", "warn", "error"
        //  container {HTMLElement|String} ID or node reference of the container (required)
        //  replaces  {Object} a Notice object, ID, or DOM node that this instance will replace
        // -------------------------------------------------------------------------------------
        var Notice = function(id, opts) {
            if (id) {
                if (typeof id === "object") {
                    opts = id;
                    id = DOM.generateId();
                }
            } else {
                id = DOM.generateId();
            }

            Notice.superclass.constructor.call(this, id, opts);
        };

        // Enum of the levels
        Notice.LEVELS = {
            success: "success",
            info: "info",
            error: "error",
            warn: "warn"
        };

        // Common notice container class name
        Notice.CLASS = "cjt-notice";

        // Notice container sub-classes
        Notice.CLASSES = {
            success: "cjt-notice-success",
            info: "cjt-notice-info",
            warn: "cjt-notice-warn",
            error: "cjt-notice-error"
        };

        YAHOO.lang.extend(Notice, YAHOO.widget.Module, {
            render: function(render_obj, mod_el) {
                var container;
                if (render_obj) {
                    container = DOM.get(render_obj);
                }

                if (container) {
                    this.cfg.queueProperty("container", container);
                } else {
                    var container_property = this.cfg.getProperty("container");
                    container = DOM.get(container_property);

                    if (!container) {
                        container = document.body;
                        this.cfg.queueProperty("container", container);
                    }
                }

                DOM.addClass(container, "cjt-notice-container");

                if (EVENT.DOMReady) {
                    var visible = this.cfg.getProperty("visible");
                    if (visible) {
                        this.element.style.display = "none";
                        this.renderEvent.subscribe(function do_vis() {
                            this.renderEvent.unsubscribe(do_vis);
                            this.animated_show();
                        });
                    }
                }

                return Notice.superclass.render.call(this, container, mod_el);
            },

            init: function(el, opts) {
                Notice.superclass.init.call(this, el /* , opts */ );

                this.beforeInitEvent.fire(Notice);

                DOM.addClass(this.element, Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Notice);
            },

            animated_show: function() {
                this.beforeShowEvent.fire();

                var replacee = this.cfg.getProperty("replaces");
                if (replacee) {
                    if (typeof replacee === "string") {
                        replacee = DOM.get(replacee);
                    } else if (replacee instanceof Notice) {
                        replacee = replacee.element;
                    }
                }
                if (replacee) {
                    replacee.parentNode.removeChild(replacee);

                    /*
                    Removed until it can be fixed.   The commented block does not
                    replace (page_notice) if another notice is requested while an
                    annimation is in effect.

                    var container = DOM.get( this.cfg.getProperty("container") );
                    container.insertBefore( this.element, DOM.getNextSibling(replacee) || undefined );
                    var rep_slide = CPANEL.animate.slide_up( replacee );
                    console.log(replacee);
                    if ( replacee instanceof Notice ) {
                         rep_slide.onComplete.subscribe( replacee.destroy, replacee, true );
                    }
                    */
                }

                var ret = CPANEL.animate.slide_down(this.element);

                this.showEvent.fire();

                this.cfg.setProperty("visible", true, true);

                return ret;
            },

            initDefaultConfig: function() {
                Notice.superclass.initDefaultConfig.call(this);

                this.cfg.addProperty("replaces", {
                    value: null
                });
                this.cfg.addProperty("level", {
                    value: "info", // default to "info" level
                    handler: this.config_level
                });
                this.cfg.addProperty("content", {
                    value: "",
                    handler: this.config_content
                });
                this.cfg.addProperty("container", {
                    value: null
                });
            },

            config_content: function(type, args, obj) {
                var content = args[0];
                if (!this.body) {
                    this.setBody("<div class=\"cjt-notice-content\">" + content + "</div>");
                } else {
                    CPANEL.Y(this.body).one(".cjt-notice-content").innerHTML = content;
                }
                this._content_el = this.body.firstChild;
            },

            fade_out: function() {
                if (!this._fading_out && this.cfg) {
                    var fade = CPANEL.animate.fade_out(this.element);
                    if (fade) {
                        this._fading_out = fade;
                        this.after_hideEvent.subscribe(this.destroy, this, true);
                        fade.onComplete.subscribe(this.hide, this, true);
                    }
                }
            },

            config_level: function(type, args, obj) {
                var level = args[0];
                var level_class = level && Notice.CLASSES[level];
                if (level_class) {
                    if (this._level_class) {
                        DOM.replaceClass(this.element, this._level_class, level_class);
                    } else {
                        DOM.addClass(this.element, level_class);
                    }
                    this._level_class = level_class;
                }
            }
        });


        // -------------------------------------------------------------------------------------
        // Extensions to Notice for in page notifications.
        //
        // @class Page_Notice
        // @extends Notice
        // @param id {String} optional id of the content to show.
        // @param opts {Hash} first or second arugment depending on if @id is passed.
        //  content   {String} HTML content of the notice
        //  level     {String} one of "success", "info", "warn", "error"
        //  container {HTMLElement|String} ID or node reference of the container, but defaults
        //  to "cjt_pagenotice_container".
        //  replaces  {Object} a Notice object, ID, or DOM node that this instance will replace
        // -------------------------------------------------------------------------------------
        var Page_Notice = function() {
            Page_Notice.superclass.constructor.apply(this, arguments);
        };

        Page_Notice.CLASS = "cjt-pagenotice";

        Page_Notice.DEFAULT_CONTAINER_ID = "cjt_pagenotice_container";

        YAHOO.lang.extend(Page_Notice, Notice, {
            init: function(el, opts) {
                Page_Notice.superclass.init.call(this, el /* , opts */ );

                this.beforeInitEvent.fire(Page_Notice);

                DOM.addClass(this.element, Page_Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Page_Notice);
            },

            initDefaultConfig: function() {
                Page_Notice.superclass.initDefaultConfig.call(this);

                if (!this.cfg.getProperty("container")) {
                    this.cfg.queueProperty("container", Page_Notice.DEFAULT_CONTAINER_ID);
                }
            },

            render: function(container) {
                container = DOM.get(container || this.cfg.getProperty("container"));
                if (container) {
                    DOM.addClass(container, "cjt-pagenotice-container");
                }

                var args_copy = Array.prototype.slice.call(arguments, 0);
                args_copy[0] = container;

                var ret = Page_Notice.superclass.render.apply(this, args_copy);

                return ret;
            }
        });


        // -------------------------------------------------------------------------------------
        // Extensions to Page_Notice for TEMPORARY in-page notifications.
        // (The exact UI controls are not defined publicly.)
        //
        // @class Dynamic_Page_Notice
        // @extends Page_Notice
        //
        // (Same interface as Page_Notice.)
        // -------------------------------------------------------------------------------------
        var Dynamic_Page_Notice = function() {
            Dynamic_Page_Notice.superclass.constructor.apply(this, arguments);
        };

        Dynamic_Page_Notice.CLASS = "cjt-dynamic-pagenotice";

        Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME = 30;

        YAHOO.lang.extend(Dynamic_Page_Notice, Page_Notice, {
            init: function(el, opts) {
                Dynamic_Page_Notice.superclass.init.call(this, el /* , opts */ );

                this.changeBodyEvent.subscribe(this._add_close_button);
                this.changeBodyEvent.subscribe(this._add_close_link);

                this.beforeInitEvent.fire(Dynamic_Page_Notice);

                DOM.addClass(this.element, Dynamic_Page_Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Dynamic_Page_Notice);

                this.cfg.subscribeToConfigEvent("content", this._reset_close_link, this, true);
            },

            _add_close_link: function() {
                var close_text = LOCALE.maketext("Click to close.");
                var close_html = '<a href="javascript:void(0)">' + close_text + "</a>";

                var close_link;

                // Can't add to innerHTML because that will recreate
                // DOM nodes, which may have listeners on them.
                var nodes = CPANEL.dom.create_from_markup(close_html);
                close_link = nodes[0];

                DOM.addClass(close_link, "cjt-dynamic-pagenotice-close-link");
                EVENT.on(close_link, "click", this.fade_out, this, true);
                this.body.appendChild(close_link);

                if (this.cfg.getProperty("level") === "success") {
                    close_link.innerHTML += ' [<span id="' + this.element.id + '_countdown">' + Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME + "</span>]";
                    this._countdown_timeout = CPANEL.util.countdown(this.element.id + "_countdown", this.fade_out.bind(this));
                }
            },

            _reset_close_link: function() {
                if (this.cfg.getProperty("level") === "success") {
                    var span_el = DOM.get(this.element.id + "_countdown");
                    span_el.innerHTML = Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME;
                }
            },

            /**
             * Attached to changeBodyEvent when "closebutton" is enabled.
             *
             * @method _add_close_button
             * @private
             */
            _add_close_button: function() {
                if (!this._cjt_close_button || !DOM.inDocument(this._cjt_close_button)) {
                    this.body.innerHTML += closeButton;
                    this._cjt_close_button = CPANEL.Y(this.body).one(".cjt-dynamic-pagenotice-close-button");

                    EVENT.on(this._cjt_close_button, "click", this.fade_out, this, true);
                }
            },

            /**
             * A reference to the close button.
             *
             * @property _cjt_close_button
             * @private
             */
            _cjt_close_button: null
        });

        // Publish the public interface
        CPANEL.widgets.Notice = Notice;
        CPANEL.widgets.Page_Notice = Page_Notice;
        CPANEL.widgets.Dynamic_Page_Notice = Dynamic_Page_Notice;

        // CSS for this doesn't work in IE<8. IE8 support may be possible,
        // but getting the wrapper to "contain" the <select> "tightly"
        // may be more trouble than its worth. So, we only do this for
        // IE9+.
        // Sets classes "cjt-wrapped-select" and "cjt-wrapped-select-skin"
        // Sets ID "(ID)-cjt-wrapped-select" if the <select> has an ID
        var _prototype_wrapper;
        var _arrow_key_codes = {
            37: 1,
            38: 1,
            39: 1,
            40: 1
        };
        var Wrapped_Select = function(sel) {
            if (YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9)) {
                return;
            }

            if (typeof sel === "string") {
                sel = DOM.get(sel);
            }

            if (sel.multiple) {
                throw "Can't use Wrapped_Select on multi-select!";
            }

            if (!_prototype_wrapper) {
                var dummy = document.createElement("div");
                dummy.innerHTML = "<div class='cjt-wrapped-select'><div class='cjt-wrapped-select-skin'></div><div class='cjt-wrapped-select-icon'></div></div>";
                _prototype_wrapper = dummy.removeChild(dummy.firstChild);
            }

            var wrapper = this._wrapper = _prototype_wrapper.cloneNode(true);

            if (sel.id) {
                wrapper.id = sel.id + "-cjt-wrapped-select";
            }

            this._select = sel;
            this._options = sel.options;
            this._label = wrapper.firstChild;

            this.synchronize_label();

            sel.parentNode.insertBefore(wrapper, sel);
            wrapper.insertBefore(sel, this._label);

            EVENT.on(sel, "keydown", function(e) {
                if (_arrow_key_codes[e.keyCode]) {
                    setTimeout(function() {
                        sel.blur();
                        sel.focus();
                    }, 1);
                }
            });
            EVENT.on(sel, "change", this.synchronize_label, this, true);
        };
        Wrapped_Select.prototype.synchronize_label = function() {
            if (this._select) {
                var label = "";
                var idx = this._select.selectedIndex;
                if (idx > -1) {
                    var opt = this._options[idx];
                    label = CPANEL.util.get_text_content(opt) || opt.value;
                }
                CPANEL.util.set_text_content(this._label, label);
            } else {
                this.synchronize_label = Object; // Use an existing function.
            }
        };
        CPANEL.widgets.Wrapped_Select = Wrapped_Select;

        /**
         * This YUI Tooltip subclass adds a mousedown listener for touch displays.
         * NOTE: To accomplish this, we have to twiddle with some privates.
         *
         * Arguments, parameters, and usage are the same as YUI Tooltip, except
         * for adding the *MouseDown events and methods.
         *
         * @class CPANEL.widgets.Touch_Tooltip
         * @extends YAHOO.widget.Tooltip
         * @constructor
         * @param {string|object} el The ID of the tooltip, or the config object
         * @param {object} cfg If an ID was given in the first argument, this is the config object.
         */
        var Touch_Tooltip = function(el, cfg) {
            if (!cfg) {
                cfg = el;
                el = null;
            }
            if (!el) {
                el = DOM.generateId();
            }

            return YAHOO.widget.Tooltip.call(this, el, cfg);
        };
        var CustomEvent = YAHOO.util.CustomEvent;
        var Event = EVENT;
        YAHOO.lang.extend(Touch_Tooltip, YAHOO.widget.Tooltip, {

            /**
             * See the YUI Tooltip docs.
             */
            initEvents: function() {
                Touch_Tooltip.superclass.initEvents.call(this);
                var SIGNATURE = CustomEvent.LIST;

                this.contextMouseDownEvent = this.createEvent("contextMouseDown");
                this.contextMouseDownEvent.signature = SIGNATURE;
            },

            /**
             * Similar to other functions defined in the YUI Tooltip prototype.
             * See the YUI Tooltip docs.
             */
            onContextMouseDown: function(e, obj) {
                var context = this;

                // Fire first, to honor disabled set in the listner
                if (obj.fireEvent("contextMouseDown", context, e) !== false && !obj.cfg.getProperty("disabled")) {

                    var showdelay = obj.cfg.getProperty("showdelay");
                    var hidedelay = obj.cfg.getProperty("hidedelay");
                    obj.cfg.setProperty("showdelay", 0);
                    obj.cfg.setProperty("hidedelay", 0);

                    if (obj.cfg.getProperty("visible")) {
                        obj.doHide();
                    } else {
                        obj.doShow();
                    }

                    obj.cfg.setProperty("showdelay", showdelay);
                    obj.cfg.setProperty("hidedelay", hidedelay);
                }
            },

            /**
             * See the YUI Tooltip docs.
             * NB: copied from Tooltip; tweaks made where noted
             */
            configContext: function(type, args, obj) {

                // Not in Tooltip natively, but that's probably an oversight.
                YAHOO.widget.Overlay.prototype.configContext.apply(this, arguments);

                var context = args[0],
                    aElements,
                    nElements,
                    oElement,
                    i;

                if (context) {

                    // Normalize parameter into an array
                    if (!(context instanceof Array)) {
                        if (typeof context == "string") {
                            this.cfg.setProperty("context", [document.getElementById(context)], true);
                        } else { // Assuming this is an element
                            this.cfg.setProperty("context", [context], true);
                        }
                        context = this.cfg.getProperty("context");
                    }

                    // Remove any existing mouseover/mouseout listeners
                    this._removeEventListeners();

                    // Add mouseover/mouseout listeners to context elements
                    this._context = context;

                    aElements = this._context;

                    if (aElements) {
                        nElements = aElements.length;
                        if (nElements > 0) {
                            i = nElements - 1;
                            do {
                                oElement = aElements[i];
                                Event.on(oElement, "mouseover", this.onContextMouseOver, this);
                                Event.on(oElement, "mousemove", this.onContextMouseMove, this);
                                Event.on(oElement, "mouseout", this.onContextMouseOut, this);

                                // THIS IS ADDED.
                                Event.on(oElement, "mousedown", this.onContextMouseDown, this);
                            }
                            while (i--);
                        }
                    }
                }
            },

            /**
             * See the YUI Tooltip docs.
             * NB: copied from Tooltip; tweaks made where noted
             */
            _removeEventListeners: function() {
                Touch_Tooltip.superclass._removeEventListeners.call(this);

                var aElements = this._context,
                    nElements,
                    oElement,
                    i;

                if (aElements) {
                    nElements = aElements.length;
                    if (nElements > 0) {
                        i = nElements - 1;
                        do {
                            oElement = aElements[i];
                            Event.removeListener(oElement, "mouseover", this.onContextMouseOver);
                            Event.removeListener(oElement, "mousemove", this.onContextMouseMove);
                            Event.removeListener(oElement, "mouseout", this.onContextMouseOut);

                            // THIS IS ADDED.
                            Event.removeListener(oElement, "mousedown", this.onContextMouseDown);
                        }
                        while (i--);
                    }
                }
            }
        });
        CPANEL.widgets.Touch_Tooltip = Touch_Tooltip;

    } // end else statement
})();

//--- end /usr/local/cpanel/base/cjt/widgets.js ---

//--- start /usr/local/cpanel/base/cjt/yuiextras.js ---
/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var DOM = YAHOO.util.Dom;
    var EVENT = YAHOO.util.Event;
    var document = window.document;

    // Add a "noscroll" config option: the panel will not scroll with the page.
    // Works by wrapping the panel element in a position:fixed <div>.
    // NOTE: This only works when initializing the panel.
    if (("YAHOO" in window) && YAHOO.widget && YAHOO.widget.Panel) {
        var _old_init = YAHOO.widget.Panel.prototype.init;
        YAHOO.widget.Panel.prototype.init = function(el, userConfig) {
            _old_init.apply(this, arguments);

            this.cfg.addProperty("noscroll", {
                value: !!userConfig && !!userConfig.noscroll
            });
        };

        var _old_initEvents = YAHOO.widget.Panel.prototype.initEvents;
        YAHOO.widget.Panel.prototype.initEvents = function() {
            _old_initEvents.apply(this, arguments);

            this.renderEvent.subscribe(function() {
                if (this.cfg.getProperty("noscroll")) {
                    var wrapper_div = document.createElement("div");
                    wrapper_div.style.position = "fixed";

                    var parent_node = this.element.parentNode;
                    parent_node.insertBefore(wrapper_div, this.element);
                    wrapper_div.appendChild(this.element);
                    this.wrapper = wrapper_div;
                }
            });
        };
    }


    // YUI 2's Overlay context property does not factor in margins of either the
    // context element or the overlay element. This change makes it look for a
    // margin on the overlay element (not the context element) and add that to
    // whatever offset may have been passed in.
    // See YUI 3 feature request 25298897.
    if (!YAHOO.widget.Overlay._offset_uses_margin) {
        var Overlay = YAHOO.widget.Overlay;
        var _align = Overlay.prototype.align;
        var _margins_to_check = {};
        _margins_to_check[Overlay.TOP_LEFT] = ["margin-top", "margin-left"];
        _margins_to_check[Overlay.TOP_RIGHT] = ["margin-top", "margin-right"];
        _margins_to_check[Overlay.BOTTOM_LEFT] = ["margin-bottom", "margin-left"];
        _margins_to_check[Overlay.BOTTOM_RIGHT] = ["margin-bottom", "margin-right"];

        Overlay.prototype.align = function(el_align, context_align, xy_offset) {

            // Most of the time that this is called, we want to query the
            // object itself for these configuration parameters.
            if (!el_align) {
                if (this.cfg) {
                    var this_context = this.cfg.getProperty("context");
                    if (this_context) {
                        el_align = this_context[1];

                        if (!context_align) {
                            context_align = this_context[2];
                        }

                        if (!xy_offset) {
                            xy_offset = this_context[4];
                        }
                    }
                }
            }

            if (!el_align) {
                return _align.apply(this, arguments);
            }

            var el = this.element;
            var margins = _margins_to_check[el_align];
            var el_y_offset = parseInt(DOM.getStyle(el, margins[0]), 10) || 0;
            var el_x_offset = parseInt(DOM.getStyle(el, margins[1]), 10) || 0;

            if (el_x_offset) {
                var x_offset_is_negative = (el_align === Overlay.BOTTOM_RIGHT) || (el_align === Overlay.TOP_RIGHT);
                if (x_offset_is_negative) {
                    el_x_offset *= -1;
                }
            }

            if (el_y_offset) {
                var y_offset_is_negative = (el_align === Overlay.BOTTOM_LEFT) || (el_align === Overlay.BOTTOM_RIGHT);
                if (y_offset_is_negative) {
                    el_y_offset *= -1;
                }
            }

            if (el_x_offset || el_y_offset) {
                var new_xy_offset;
                if (xy_offset) {
                    new_xy_offset = [xy_offset[0] + el_x_offset, xy_offset[1] + el_y_offset];
                } else {
                    new_xy_offset = [el_x_offset, el_y_offset];
                }
                return _align.call(this, el_align, context_align, new_xy_offset);
            } else {
                return _align.apply(this, arguments);
            }
        };

        Overlay._offset_uses_margin = true;
    }

    // HTML forms don't usually submit from ENTER unless they have a submit
    // button, which YUI Dialog forms do not have by design. Moreover, they *do*
    // submit if there is just one text field. To smooth out these peculiarities:
    // 1) Add a dummy <input type="text"> to kill native ENTER submission.
    // 2) Listen for keydown events on a dialog box and run submit() from them.
    if (!YAHOO.widget.Dialog._handles_enter) {
        var _registerForm = YAHOO.widget.Dialog.prototype.registerForm;
        YAHOO.widget.Dialog.prototype.registerForm = function() {
            _registerForm.apply(this, arguments);

            if (!this._cjt_dummy_input) {
                var dummy_input = document.createElement("input");
                dummy_input.style.display = "none";
                this.form.appendChild(dummy_input);
                this._cjt_dummy_input = dummy_input;
            }
        };

        // YUI 2 KeyListener does not make its own copy of the key data object
        // that it receives when the KeyListener is created; as a result, it is
        // possible to alter the listener by changing the key data object after
        // creating the KeyListener. It's also problematic that KeyListener doesn't
        // make that information available to us after creating the listener.
        // We fix both of these issues here.
        var _key_listener = YAHOO.util.KeyListener;
        var new_key_listener = function(attach_to, key_data, handler, event) {
            var new_key_data = {};
            for (var key in key_data) {
                new_key_data[key] = key_data[key];
            }
            this.key_data = new_key_data;

            _key_listener.call(this, attach_to, new_key_data, handler, event);
        };
        YAHOO.lang.extend(new_key_listener, _key_listener);
        YAHOO.lang.augmentObject(new_key_listener, _key_listener); // static properties
        YAHOO.util.KeyListener = new_key_listener;

        // We want all dialog boxes to submit when their form receives ENTER,
        // unless the ENTER went to a <textarea> or <select>.
        // Check for this immediately after init();
        var _init = YAHOO.widget.Dialog.prototype.init;
        var _non_submit = {
            textarea: true,
            select: true
        };
        YAHOO.widget.Dialog.prototype.init = function(el, cfg) {
            var ret = _init.apply(this, arguments);

            var key_listeners = this.cfg.getProperty("keylisteners");

            var need_to_add_enter_key_listener = !key_listeners;

            if (key_listeners) {
                if (!(key_listeners instanceof Array)) {
                    key_listeners = [key_listeners];
                }

                need_to_add_enter_key_listener = !key_listeners.some(function(kl) {
                    if (!kl.key_data) {
                        return false;
                    }

                    if (kl.key_data.keys === 13) {
                        return true;
                    }

                    if (kl.key_data.indexOf && kl.key_data.indexOf(13) !== -1) {
                        return true;
                    }

                    return false;
                });
            } else {
                key_listeners = [];
                need_to_add_enter_key_listener = true;
            }

            if (need_to_add_enter_key_listener) {
                var the_dialog = this;
                key_listeners.push(new YAHOO.util.KeyListener(document.body, {
                    keys: 13
                }, function(type, args) {
                    if (the_dialog.cfg.getProperty("postmethod") !== "form") {
                        var original = EVENT.getTarget(args[1]);
                        if (original && !_non_submit[original.nodeName.toLowerCase()] && original.form === the_dialog.form) {
                            the_dialog.submit();
                        }
                    }
                }));

                this.cfg.setProperty("keylisteners", key_listeners);
            }

            return ret;
        };

        YAHOO.widget.Dialog._handles_enter = true;
    }

    // Allow YUI Dialog buttons to set "classes" in their definitions
    var _configButtons = YAHOO.widget.Dialog.prototype.configButtons;
    YAHOO.widget.Dialog.prototype.configButtons = function() {
        var ret = _configButtons.apply(this, arguments);

        var button_defs = this.cfg.getProperty("buttons");
        if (!button_defs || !button_defs.length) {
            return ret;
        }

        var buttons = this.getButtons();
        if (!buttons.length) {
            return ret;
        }

        var yui_button = YAHOO.widget.Button && (buttons[0] instanceof YAHOO.widget.Button);

        for (var b = buttons.length - 1; b >= 0; b--) {
            var cur_button = buttons[b];
            var classes = button_defs[b].classes;
            if (classes) {
                if (classes instanceof Array) {
                    classes = classes.join(" ");
                }

                if (yui_button) {
                    cur_button.addClass(classes);
                } else {
                    DOM.addClass(cur_button, classes);
                }
            }
        }

        return ret;
    };


    // http://yuilibrary.com/projects/yui2/ticket/2529451
    //
    // Custom Event: after_hideEvent
    //  This allows us to tell YUI to destroy() a Module once it's hidden.
    //
    // If we're animated, then just execute as the last hideEvent subscriber.
    // If not, then execute immeditaely after hide() is done.
    //
    // We have to do the two cases separately because of the call to
    // cfg.configChangedEvent.fire() immediately after hideEvent.fire() in
    // cfg.setProperty().
    var modpro = YAHOO.widget.Module.prototype;
    var init_ev = modpro.initEvents;
    modpro.initEvents = function() {
        init_ev.apply(this, arguments);
        this.after_hideEvent = this.createEvent("after_hide");
        this.after_hideEvent.signature = YAHOO.util.CustomEvent.LIST;
    };
    var hide = modpro.hide;
    modpro.hide = function() {
        var delayed = this.cfg.getProperty("effect");
        if (delayed) {
            this.hideEvent.subscribe(function afterward() {
                this.hideEvent.unsubscribe(afterward);
                this.after_hideEvent.fire();
            });
        }
        hide.apply(this, arguments);
        if (!delayed) {
            this.after_hideEvent.fire();
        }
    };

})(window);

//--- end /usr/local/cpanel/base/cjt/yuiextras.js ---
