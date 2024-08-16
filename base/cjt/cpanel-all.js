
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

//--- start /usr/local/cpanel/base/cjt/jquery.js ---
/*!
 * jQuery JavaScript Library v3.6.0
 * https://jquery.com/
 *
 * Includes Sizzle.js
 * https://sizzlejs.com/
 *
 * Copyright OpenJS Foundation and other contributors
 * Released under the MIT license
 * https://jquery.org/license
 *
 * Date: 2021-03-02T17:08Z
 */
( function( global, factory ) {

	"use strict";

	if ( typeof module === "object" && typeof module.exports === "object" ) {

		// For CommonJS and CommonJS-like environments where a proper `window`
		// is present, execute the factory and get jQuery.
		// For environments that do not have a `window` with a `document`
		// (such as Node.js), expose a factory as module.exports.
		// This accentuates the need for the creation of a real `window`.
		// e.g. var jQuery = require("jquery")(window);
		// See ticket #14549 for more info.
		module.exports = global.document ?
			factory( global, true ) :
			function( w ) {
				if ( !w.document ) {
					throw new Error( "jQuery requires a window with a document" );
				}
				return factory( w );
			};
	} else {
		factory( global );
	}

// Pass this if window is not defined yet
} )( typeof window !== "undefined" ? window : this, function( window, noGlobal ) {

// Edge <= 12 - 13+, Firefox <=18 - 45+, IE 10 - 11, Safari 5.1 - 9+, iOS 6 - 9.1
// throw exceptions when non-strict code (e.g., ASP.NET 4.5) accesses strict mode
// arguments.callee.caller (trac-13335). But as of jQuery 3.0 (2016), strict mode should be common
// enough that all such attempts are guarded in a try block.
"use strict";

var arr = [];

var getProto = Object.getPrototypeOf;

var slice = arr.slice;

var flat = arr.flat ? function( array ) {
	return arr.flat.call( array );
} : function( array ) {
	return arr.concat.apply( [], array );
};


var push = arr.push;

var indexOf = arr.indexOf;

var class2type = {};

var toString = class2type.toString;

var hasOwn = class2type.hasOwnProperty;

var fnToString = hasOwn.toString;

var ObjectFunctionString = fnToString.call( Object );

var support = {};

var isFunction = function isFunction( obj ) {

		// Support: Chrome <=57, Firefox <=52
		// In some browsers, typeof returns "function" for HTML <object> elements
		// (i.e., `typeof document.createElement( "object" ) === "function"`).
		// We don't want to classify *any* DOM node as a function.
		// Support: QtWeb <=3.8.5, WebKit <=534.34, wkhtmltopdf tool <=0.12.5
		// Plus for old WebKit, typeof returns "function" for HTML collections
		// (e.g., `typeof document.getElementsByTagName("div") === "function"`). (gh-4756)
		return typeof obj === "function" && typeof obj.nodeType !== "number" &&
			typeof obj.item !== "function";
	};


var isWindow = function isWindow( obj ) {
		return obj != null && obj === obj.window;
	};


var document = window.document;



	var preservedScriptAttributes = {
		type: true,
		src: true,
		nonce: true,
		noModule: true
	};

	function DOMEval( code, node, doc ) {
		doc = doc || document;

		var i, val,
			script = doc.createElement( "script" );

		script.text = code;
		if ( node ) {
			for ( i in preservedScriptAttributes ) {

				// Support: Firefox 64+, Edge 18+
				// Some browsers don't support the "nonce" property on scripts.
				// On the other hand, just using `getAttribute` is not enough as
				// the `nonce` attribute is reset to an empty string whenever it
				// becomes browsing-context connected.
				// See https://github.com/whatwg/html/issues/2369
				// See https://html.spec.whatwg.org/#nonce-attributes
				// The `node.getAttribute` check was added for the sake of
				// `jQuery.globalEval` so that it can fake a nonce-containing node
				// via an object.
				val = node[ i ] || node.getAttribute && node.getAttribute( i );
				if ( val ) {
					script.setAttribute( i, val );
				}
			}
		}
		doc.head.appendChild( script ).parentNode.removeChild( script );
	}


function toType( obj ) {
	if ( obj == null ) {
		return obj + "";
	}

	// Support: Android <=2.3 only (functionish RegExp)
	return typeof obj === "object" || typeof obj === "function" ?
		class2type[ toString.call( obj ) ] || "object" :
		typeof obj;
}
/* global Symbol */
// Defining this global in .eslintrc.json would create a danger of using the global
// unguarded in another place, it seems safer to define global only for this module



var
	version = "3.6.0",

	// Define a local copy of jQuery
	jQuery = function( selector, context ) {

		// The jQuery object is actually just the init constructor 'enhanced'
		// Need init if jQuery is called (just allow error to be thrown if not included)
		return new jQuery.fn.init( selector, context );
	};

jQuery.fn = jQuery.prototype = {

	// The current version of jQuery being used
	jquery: version,

	constructor: jQuery,

	// The default length of a jQuery object is 0
	length: 0,

	toArray: function() {
		return slice.call( this );
	},

	// Get the Nth element in the matched element set OR
	// Get the whole matched element set as a clean array
	get: function( num ) {

		// Return all the elements in a clean array
		if ( num == null ) {
			return slice.call( this );
		}

		// Return just the one element from the set
		return num < 0 ? this[ num + this.length ] : this[ num ];
	},

	// Take an array of elements and push it onto the stack
	// (returning the new matched element set)
	pushStack: function( elems ) {

		// Build a new jQuery matched element set
		var ret = jQuery.merge( this.constructor(), elems );

		// Add the old object onto the stack (as a reference)
		ret.prevObject = this;

		// Return the newly-formed element set
		return ret;
	},

	// Execute a callback for every element in the matched set.
	each: function( callback ) {
		return jQuery.each( this, callback );
	},

	map: function( callback ) {
		return this.pushStack( jQuery.map( this, function( elem, i ) {
			return callback.call( elem, i, elem );
		} ) );
	},

	slice: function() {
		return this.pushStack( slice.apply( this, arguments ) );
	},

	first: function() {
		return this.eq( 0 );
	},

	last: function() {
		return this.eq( -1 );
	},

	even: function() {
		return this.pushStack( jQuery.grep( this, function( _elem, i ) {
			return ( i + 1 ) % 2;
		} ) );
	},

	odd: function() {
		return this.pushStack( jQuery.grep( this, function( _elem, i ) {
			return i % 2;
		} ) );
	},

	eq: function( i ) {
		var len = this.length,
			j = +i + ( i < 0 ? len : 0 );
		return this.pushStack( j >= 0 && j < len ? [ this[ j ] ] : [] );
	},

	end: function() {
		return this.prevObject || this.constructor();
	},

	// For internal use only.
	// Behaves like an Array's method, not like a jQuery method.
	push: push,
	sort: arr.sort,
	splice: arr.splice
};

jQuery.extend = jQuery.fn.extend = function() {
	var options, name, src, copy, copyIsArray, clone,
		target = arguments[ 0 ] || {},
		i = 1,
		length = arguments.length,
		deep = false;

	// Handle a deep copy situation
	if ( typeof target === "boolean" ) {
		deep = target;

		// Skip the boolean and the target
		target = arguments[ i ] || {};
		i++;
	}

	// Handle case when target is a string or something (possible in deep copy)
	if ( typeof target !== "object" && !isFunction( target ) ) {
		target = {};
	}

	// Extend jQuery itself if only one argument is passed
	if ( i === length ) {
		target = this;
		i--;
	}

	for ( ; i < length; i++ ) {

		// Only deal with non-null/undefined values
		if ( ( options = arguments[ i ] ) != null ) {

			// Extend the base object
			for ( name in options ) {
				copy = options[ name ];

				// Prevent Object.prototype pollution
				// Prevent never-ending loop
				if ( name === "__proto__" || target === copy ) {
					continue;
				}

				// Recurse if we're merging plain objects or arrays
				if ( deep && copy && ( jQuery.isPlainObject( copy ) ||
					( copyIsArray = Array.isArray( copy ) ) ) ) {
					src = target[ name ];

					// Ensure proper type for the source value
					if ( copyIsArray && !Array.isArray( src ) ) {
						clone = [];
					} else if ( !copyIsArray && !jQuery.isPlainObject( src ) ) {
						clone = {};
					} else {
						clone = src;
					}
					copyIsArray = false;

					// Never move original objects, clone them
					target[ name ] = jQuery.extend( deep, clone, copy );

				// Don't bring in undefined values
				} else if ( copy !== undefined ) {
					target[ name ] = copy;
				}
			}
		}
	}

	// Return the modified object
	return target;
};

jQuery.extend( {

	// Unique for each copy of jQuery on the page
	expando: "jQuery" + ( version + Math.random() ).replace( /\D/g, "" ),

	// Assume jQuery is ready without the ready module
	isReady: true,

	error: function( msg ) {
		throw new Error( msg );
	},

	noop: function() {},

	isPlainObject: function( obj ) {
		var proto, Ctor;

		// Detect obvious negatives
		// Use toString instead of jQuery.type to catch host objects
		if ( !obj || toString.call( obj ) !== "[object Object]" ) {
			return false;
		}

		proto = getProto( obj );

		// Objects with no prototype (e.g., `Object.create( null )`) are plain
		if ( !proto ) {
			return true;
		}

		// Objects with prototype are plain iff they were constructed by a global Object function
		Ctor = hasOwn.call( proto, "constructor" ) && proto.constructor;
		return typeof Ctor === "function" && fnToString.call( Ctor ) === ObjectFunctionString;
	},

	isEmptyObject: function( obj ) {
		var name;

		for ( name in obj ) {
			return false;
		}
		return true;
	},

	// Evaluates a script in a provided context; falls back to the global one
	// if not specified.
	globalEval: function( code, options, doc ) {
		DOMEval( code, { nonce: options && options.nonce }, doc );
	},

	each: function( obj, callback ) {
		var length, i = 0;

		if ( isArrayLike( obj ) ) {
			length = obj.length;
			for ( ; i < length; i++ ) {
				if ( callback.call( obj[ i ], i, obj[ i ] ) === false ) {
					break;
				}
			}
		} else {
			for ( i in obj ) {
				if ( callback.call( obj[ i ], i, obj[ i ] ) === false ) {
					break;
				}
			}
		}

		return obj;
	},

	// results is for internal usage only
	makeArray: function( arr, results ) {
		var ret = results || [];

		if ( arr != null ) {
			if ( isArrayLike( Object( arr ) ) ) {
				jQuery.merge( ret,
					typeof arr === "string" ?
						[ arr ] : arr
				);
			} else {
				push.call( ret, arr );
			}
		}

		return ret;
	},

	inArray: function( elem, arr, i ) {
		return arr == null ? -1 : indexOf.call( arr, elem, i );
	},

	// Support: Android <=4.0 only, PhantomJS 1 only
	// push.apply(_, arraylike) throws on ancient WebKit
	merge: function( first, second ) {
		var len = +second.length,
			j = 0,
			i = first.length;

		for ( ; j < len; j++ ) {
			first[ i++ ] = second[ j ];
		}

		first.length = i;

		return first;
	},

	grep: function( elems, callback, invert ) {
		var callbackInverse,
			matches = [],
			i = 0,
			length = elems.length,
			callbackExpect = !invert;

		// Go through the array, only saving the items
		// that pass the validator function
		for ( ; i < length; i++ ) {
			callbackInverse = !callback( elems[ i ], i );
			if ( callbackInverse !== callbackExpect ) {
				matches.push( elems[ i ] );
			}
		}

		return matches;
	},

	// arg is for internal usage only
	map: function( elems, callback, arg ) {
		var length, value,
			i = 0,
			ret = [];

		// Go through the array, translating each of the items to their new values
		if ( isArrayLike( elems ) ) {
			length = elems.length;
			for ( ; i < length; i++ ) {
				value = callback( elems[ i ], i, arg );

				if ( value != null ) {
					ret.push( value );
				}
			}

		// Go through every key on the object,
		} else {
			for ( i in elems ) {
				value = callback( elems[ i ], i, arg );

				if ( value != null ) {
					ret.push( value );
				}
			}
		}

		// Flatten any nested arrays
		return flat( ret );
	},

	// A global GUID counter for objects
	guid: 1,

	// jQuery.support is not used in Core but other projects attach their
	// properties to it so it needs to exist.
	support: support
} );

if ( typeof Symbol === "function" ) {
	jQuery.fn[ Symbol.iterator ] = arr[ Symbol.iterator ];
}

// Populate the class2type map
jQuery.each( "Boolean Number String Function Array Date RegExp Object Error Symbol".split( " " ),
	function( _i, name ) {
		class2type[ "[object " + name + "]" ] = name.toLowerCase();
	} );

function isArrayLike( obj ) {

	// Support: real iOS 8.2 only (not reproducible in simulator)
	// `in` check used to prevent JIT error (gh-2145)
	// hasOwn isn't used here due to false negatives
	// regarding Nodelist length in IE
	var length = !!obj && "length" in obj && obj.length,
		type = toType( obj );

	if ( isFunction( obj ) || isWindow( obj ) ) {
		return false;
	}

	return type === "array" || length === 0 ||
		typeof length === "number" && length > 0 && ( length - 1 ) in obj;
}
var Sizzle =
/*!
 * Sizzle CSS Selector Engine v2.3.6
 * https://sizzlejs.com/
 *
 * Copyright JS Foundation and other contributors
 * Released under the MIT license
 * https://js.foundation/
 *
 * Date: 2021-02-16
 */
( function( window ) {
var i,
	support,
	Expr,
	getText,
	isXML,
	tokenize,
	compile,
	select,
	outermostContext,
	sortInput,
	hasDuplicate,

	// Local document vars
	setDocument,
	document,
	docElem,
	documentIsHTML,
	rbuggyQSA,
	rbuggyMatches,
	matches,
	contains,

	// Instance-specific data
	expando = "sizzle" + 1 * new Date(),
	preferredDoc = window.document,
	dirruns = 0,
	done = 0,
	classCache = createCache(),
	tokenCache = createCache(),
	compilerCache = createCache(),
	nonnativeSelectorCache = createCache(),
	sortOrder = function( a, b ) {
		if ( a === b ) {
			hasDuplicate = true;
		}
		return 0;
	},

	// Instance methods
	hasOwn = ( {} ).hasOwnProperty,
	arr = [],
	pop = arr.pop,
	pushNative = arr.push,
	push = arr.push,
	slice = arr.slice,

	// Use a stripped-down indexOf as it's faster than native
	// https://jsperf.com/thor-indexof-vs-for/5
	indexOf = function( list, elem ) {
		var i = 0,
			len = list.length;
		for ( ; i < len; i++ ) {
			if ( list[ i ] === elem ) {
				return i;
			}
		}
		return -1;
	},

	booleans = "checked|selected|async|autofocus|autoplay|controls|defer|disabled|hidden|" +
		"ismap|loop|multiple|open|readonly|required|scoped",

	// Regular expressions

	// http://www.w3.org/TR/css3-selectors/#whitespace
	whitespace = "[\\x20\\t\\r\\n\\f]",

	// https://www.w3.org/TR/css-syntax-3/#ident-token-diagram
	identifier = "(?:\\\\[\\da-fA-F]{1,6}" + whitespace +
		"?|\\\\[^\\r\\n\\f]|[\\w-]|[^\0-\\x7f])+",

	// Attribute selectors: http://www.w3.org/TR/selectors/#attribute-selectors
	attributes = "\\[" + whitespace + "*(" + identifier + ")(?:" + whitespace +

		// Operator (capture 2)
		"*([*^$|!~]?=)" + whitespace +

		// "Attribute values must be CSS identifiers [capture 5]
		// or strings [capture 3 or capture 4]"
		"*(?:'((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\"|(" + identifier + "))|)" +
		whitespace + "*\\]",

	pseudos = ":(" + identifier + ")(?:\\((" +

		// To reduce the number of selectors needing tokenize in the preFilter, prefer arguments:
		// 1. quoted (capture 3; capture 4 or capture 5)
		"('((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\")|" +

		// 2. simple (capture 6)
		"((?:\\\\.|[^\\\\()[\\]]|" + attributes + ")*)|" +

		// 3. anything else (capture 2)
		".*" +
		")\\)|)",

	// Leading and non-escaped trailing whitespace, capturing some non-whitespace characters preceding the latter
	rwhitespace = new RegExp( whitespace + "+", "g" ),
	rtrim = new RegExp( "^" + whitespace + "+|((?:^|[^\\\\])(?:\\\\.)*)" +
		whitespace + "+$", "g" ),

	rcomma = new RegExp( "^" + whitespace + "*," + whitespace + "*" ),
	rcombinators = new RegExp( "^" + whitespace + "*([>+~]|" + whitespace + ")" + whitespace +
		"*" ),
	rdescend = new RegExp( whitespace + "|>" ),

	rpseudo = new RegExp( pseudos ),
	ridentifier = new RegExp( "^" + identifier + "$" ),

	matchExpr = {
		"ID": new RegExp( "^#(" + identifier + ")" ),
		"CLASS": new RegExp( "^\\.(" + identifier + ")" ),
		"TAG": new RegExp( "^(" + identifier + "|[*])" ),
		"ATTR": new RegExp( "^" + attributes ),
		"PSEUDO": new RegExp( "^" + pseudos ),
		"CHILD": new RegExp( "^:(only|first|last|nth|nth-last)-(child|of-type)(?:\\(" +
			whitespace + "*(even|odd|(([+-]|)(\\d*)n|)" + whitespace + "*(?:([+-]|)" +
			whitespace + "*(\\d+)|))" + whitespace + "*\\)|)", "i" ),
		"bool": new RegExp( "^(?:" + booleans + ")$", "i" ),

		// For use in libraries implementing .is()
		// We use this for POS matching in `select`
		"needsContext": new RegExp( "^" + whitespace +
			"*[>+~]|:(even|odd|eq|gt|lt|nth|first|last)(?:\\(" + whitespace +
			"*((?:-\\d)?\\d*)" + whitespace + "*\\)|)(?=[^-]|$)", "i" )
	},

	rhtml = /HTML$/i,
	rinputs = /^(?:input|select|textarea|button)$/i,
	rheader = /^h\d$/i,

	rnative = /^[^{]+\{\s*\[native \w/,

	// Easily-parseable/retrievable ID or TAG or CLASS selectors
	rquickExpr = /^(?:#([\w-]+)|(\w+)|\.([\w-]+))$/,

	rsibling = /[+~]/,

	// CSS escapes
	// http://www.w3.org/TR/CSS21/syndata.html#escaped-characters
	runescape = new RegExp( "\\\\[\\da-fA-F]{1,6}" + whitespace + "?|\\\\([^\\r\\n\\f])", "g" ),
	funescape = function( escape, nonHex ) {
		var high = "0x" + escape.slice( 1 ) - 0x10000;

		return nonHex ?

			// Strip the backslash prefix from a non-hex escape sequence
			nonHex :

			// Replace a hexadecimal escape sequence with the encoded Unicode code point
			// Support: IE <=11+
			// For values outside the Basic Multilingual Plane (BMP), manually construct a
			// surrogate pair
			high < 0 ?
				String.fromCharCode( high + 0x10000 ) :
				String.fromCharCode( high >> 10 | 0xD800, high & 0x3FF | 0xDC00 );
	},

	// CSS string/identifier serialization
	// https://drafts.csswg.org/cssom/#common-serializing-idioms
	rcssescape = /([\0-\x1f\x7f]|^-?\d)|^-$|[^\0-\x1f\x7f-\uFFFF\w-]/g,
	fcssescape = function( ch, asCodePoint ) {
		if ( asCodePoint ) {

			// U+0000 NULL becomes U+FFFD REPLACEMENT CHARACTER
			if ( ch === "\0" ) {
				return "\uFFFD";
			}

			// Control characters and (dependent upon position) numbers get escaped as code points
			return ch.slice( 0, -1 ) + "\\" +
				ch.charCodeAt( ch.length - 1 ).toString( 16 ) + " ";
		}

		// Other potentially-special ASCII characters get backslash-escaped
		return "\\" + ch;
	},

	// Used for iframes
	// See setDocument()
	// Removing the function wrapper causes a "Permission Denied"
	// error in IE
	unloadHandler = function() {
		setDocument();
	},

	inDisabledFieldset = addCombinator(
		function( elem ) {
			return elem.disabled === true && elem.nodeName.toLowerCase() === "fieldset";
		},
		{ dir: "parentNode", next: "legend" }
	);

// Optimize for push.apply( _, NodeList )
try {
	push.apply(
		( arr = slice.call( preferredDoc.childNodes ) ),
		preferredDoc.childNodes
	);

	// Support: Android<4.0
	// Detect silently failing push.apply
	// eslint-disable-next-line no-unused-expressions
	arr[ preferredDoc.childNodes.length ].nodeType;
} catch ( e ) {
	push = { apply: arr.length ?

		// Leverage slice if possible
		function( target, els ) {
			pushNative.apply( target, slice.call( els ) );
		} :

		// Support: IE<9
		// Otherwise append directly
		function( target, els ) {
			var j = target.length,
				i = 0;

			// Can't trust NodeList.length
			while ( ( target[ j++ ] = els[ i++ ] ) ) {}
			target.length = j - 1;
		}
	};
}

function Sizzle( selector, context, results, seed ) {
	var m, i, elem, nid, match, groups, newSelector,
		newContext = context && context.ownerDocument,

		// nodeType defaults to 9, since context defaults to document
		nodeType = context ? context.nodeType : 9;

	results = results || [];

	// Return early from calls with invalid selector or context
	if ( typeof selector !== "string" || !selector ||
		nodeType !== 1 && nodeType !== 9 && nodeType !== 11 ) {

		return results;
	}

	// Try to shortcut find operations (as opposed to filters) in HTML documents
	if ( !seed ) {
		setDocument( context );
		context = context || document;

		if ( documentIsHTML ) {

			// If the selector is sufficiently simple, try using a "get*By*" DOM method
			// (excepting DocumentFragment context, where the methods don't exist)
			if ( nodeType !== 11 && ( match = rquickExpr.exec( selector ) ) ) {

				// ID selector
				if ( ( m = match[ 1 ] ) ) {

					// Document context
					if ( nodeType === 9 ) {
						if ( ( elem = context.getElementById( m ) ) ) {

							// Support: IE, Opera, Webkit
							// TODO: identify versions
							// getElementById can match elements by name instead of ID
							if ( elem.id === m ) {
								results.push( elem );
								return results;
							}
						} else {
							return results;
						}

					// Element context
					} else {

						// Support: IE, Opera, Webkit
						// TODO: identify versions
						// getElementById can match elements by name instead of ID
						if ( newContext && ( elem = newContext.getElementById( m ) ) &&
							contains( context, elem ) &&
							elem.id === m ) {

							results.push( elem );
							return results;
						}
					}

				// Type selector
				} else if ( match[ 2 ] ) {
					push.apply( results, context.getElementsByTagName( selector ) );
					return results;

				// Class selector
				} else if ( ( m = match[ 3 ] ) && support.getElementsByClassName &&
					context.getElementsByClassName ) {

					push.apply( results, context.getElementsByClassName( m ) );
					return results;
				}
			}

			// Take advantage of querySelectorAll
			if ( support.qsa &&
				!nonnativeSelectorCache[ selector + " " ] &&
				( !rbuggyQSA || !rbuggyQSA.test( selector ) ) &&

				// Support: IE 8 only
				// Exclude object elements
				( nodeType !== 1 || context.nodeName.toLowerCase() !== "object" ) ) {

				newSelector = selector;
				newContext = context;

				// qSA considers elements outside a scoping root when evaluating child or
				// descendant combinators, which is not what we want.
				// In such cases, we work around the behavior by prefixing every selector in the
				// list with an ID selector referencing the scope context.
				// The technique has to be used as well when a leading combinator is used
				// as such selectors are not recognized by querySelectorAll.
				// Thanks to Andrew Dupont for this technique.
				if ( nodeType === 1 &&
					( rdescend.test( selector ) || rcombinators.test( selector ) ) ) {

					// Expand context for sibling selectors
					newContext = rsibling.test( selector ) && testContext( context.parentNode ) ||
						context;

					// We can use :scope instead of the ID hack if the browser
					// supports it & if we're not changing the context.
					if ( newContext !== context || !support.scope ) {

						// Capture the context ID, setting it first if necessary
						if ( ( nid = context.getAttribute( "id" ) ) ) {
							nid = nid.replace( rcssescape, fcssescape );
						} else {
							context.setAttribute( "id", ( nid = expando ) );
						}
					}

					// Prefix every selector in the list
					groups = tokenize( selector );
					i = groups.length;
					while ( i-- ) {
						groups[ i ] = ( nid ? "#" + nid : ":scope" ) + " " +
							toSelector( groups[ i ] );
					}
					newSelector = groups.join( "," );
				}

				try {
					push.apply( results,
						newContext.querySelectorAll( newSelector )
					);
					return results;
				} catch ( qsaError ) {
					nonnativeSelectorCache( selector, true );
				} finally {
					if ( nid === expando ) {
						context.removeAttribute( "id" );
					}
				}
			}
		}
	}

	// All others
	return select( selector.replace( rtrim, "$1" ), context, results, seed );
}

/**
 * Create key-value caches of limited size
 * @returns {function(string, object)} Returns the Object data after storing it on itself with
 *	property name the (space-suffixed) string and (if the cache is larger than Expr.cacheLength)
 *	deleting the oldest entry
 */
function createCache() {
	var keys = [];

	function cache( key, value ) {

		// Use (key + " ") to avoid collision with native prototype properties (see Issue #157)
		if ( keys.push( key + " " ) > Expr.cacheLength ) {

			// Only keep the most recent entries
			delete cache[ keys.shift() ];
		}
		return ( cache[ key + " " ] = value );
	}
	return cache;
}

/**
 * Mark a function for special use by Sizzle
 * @param {Function} fn The function to mark
 */
function markFunction( fn ) {
	fn[ expando ] = true;
	return fn;
}

/**
 * Support testing using an element
 * @param {Function} fn Passed the created element and returns a boolean result
 */
function assert( fn ) {
	var el = document.createElement( "fieldset" );

	try {
		return !!fn( el );
	} catch ( e ) {
		return false;
	} finally {

		// Remove from its parent by default
		if ( el.parentNode ) {
			el.parentNode.removeChild( el );
		}

		// release memory in IE
		el = null;
	}
}

/**
 * Adds the same handler for all of the specified attrs
 * @param {String} attrs Pipe-separated list of attributes
 * @param {Function} handler The method that will be applied
 */
function addHandle( attrs, handler ) {
	var arr = attrs.split( "|" ),
		i = arr.length;

	while ( i-- ) {
		Expr.attrHandle[ arr[ i ] ] = handler;
	}
}

/**
 * Checks document order of two siblings
 * @param {Element} a
 * @param {Element} b
 * @returns {Number} Returns less than 0 if a precedes b, greater than 0 if a follows b
 */
function siblingCheck( a, b ) {
	var cur = b && a,
		diff = cur && a.nodeType === 1 && b.nodeType === 1 &&
			a.sourceIndex - b.sourceIndex;

	// Use IE sourceIndex if available on both nodes
	if ( diff ) {
		return diff;
	}

	// Check if b follows a
	if ( cur ) {
		while ( ( cur = cur.nextSibling ) ) {
			if ( cur === b ) {
				return -1;
			}
		}
	}

	return a ? 1 : -1;
}

/**
 * Returns a function to use in pseudos for input types
 * @param {String} type
 */
function createInputPseudo( type ) {
	return function( elem ) {
		var name = elem.nodeName.toLowerCase();
		return name === "input" && elem.type === type;
	};
}

/**
 * Returns a function to use in pseudos for buttons
 * @param {String} type
 */
function createButtonPseudo( type ) {
	return function( elem ) {
		var name = elem.nodeName.toLowerCase();
		return ( name === "input" || name === "button" ) && elem.type === type;
	};
}

/**
 * Returns a function to use in pseudos for :enabled/:disabled
 * @param {Boolean} disabled true for :disabled; false for :enabled
 */
function createDisabledPseudo( disabled ) {

	// Known :disabled false positives: fieldset[disabled] > legend:nth-of-type(n+2) :can-disable
	return function( elem ) {

		// Only certain elements can match :enabled or :disabled
		// https://html.spec.whatwg.org/multipage/scripting.html#selector-enabled
		// https://html.spec.whatwg.org/multipage/scripting.html#selector-disabled
		if ( "form" in elem ) {

			// Check for inherited disabledness on relevant non-disabled elements:
			// * listed form-associated elements in a disabled fieldset
			//   https://html.spec.whatwg.org/multipage/forms.html#category-listed
			//   https://html.spec.whatwg.org/multipage/forms.html#concept-fe-disabled
			// * option elements in a disabled optgroup
			//   https://html.spec.whatwg.org/multipage/forms.html#concept-option-disabled
			// All such elements have a "form" property.
			if ( elem.parentNode && elem.disabled === false ) {

				// Option elements defer to a parent optgroup if present
				if ( "label" in elem ) {
					if ( "label" in elem.parentNode ) {
						return elem.parentNode.disabled === disabled;
					} else {
						return elem.disabled === disabled;
					}
				}

				// Support: IE 6 - 11
				// Use the isDisabled shortcut property to check for disabled fieldset ancestors
				return elem.isDisabled === disabled ||

					// Where there is no isDisabled, check manually
					/* jshint -W018 */
					elem.isDisabled !== !disabled &&
					inDisabledFieldset( elem ) === disabled;
			}

			return elem.disabled === disabled;

		// Try to winnow out elements that can't be disabled before trusting the disabled property.
		// Some victims get caught in our net (label, legend, menu, track), but it shouldn't
		// even exist on them, let alone have a boolean value.
		} else if ( "label" in elem ) {
			return elem.disabled === disabled;
		}

		// Remaining elements are neither :enabled nor :disabled
		return false;
	};
}

/**
 * Returns a function to use in pseudos for positionals
 * @param {Function} fn
 */
function createPositionalPseudo( fn ) {
	return markFunction( function( argument ) {
		argument = +argument;
		return markFunction( function( seed, matches ) {
			var j,
				matchIndexes = fn( [], seed.length, argument ),
				i = matchIndexes.length;

			// Match elements found at the specified indexes
			while ( i-- ) {
				if ( seed[ ( j = matchIndexes[ i ] ) ] ) {
					seed[ j ] = !( matches[ j ] = seed[ j ] );
				}
			}
		} );
	} );
}

/**
 * Checks a node for validity as a Sizzle context
 * @param {Element|Object=} context
 * @returns {Element|Object|Boolean} The input node if acceptable, otherwise a falsy value
 */
function testContext( context ) {
	return context && typeof context.getElementsByTagName !== "undefined" && context;
}

// Expose support vars for convenience
support = Sizzle.support = {};

/**
 * Detects XML nodes
 * @param {Element|Object} elem An element or a document
 * @returns {Boolean} True iff elem is a non-HTML XML node
 */
isXML = Sizzle.isXML = function( elem ) {
	var namespace = elem && elem.namespaceURI,
		docElem = elem && ( elem.ownerDocument || elem ).documentElement;

	// Support: IE <=8
	// Assume HTML when documentElement doesn't yet exist, such as inside loading iframes
	// https://bugs.jquery.com/ticket/4833
	return !rhtml.test( namespace || docElem && docElem.nodeName || "HTML" );
};

/**
 * Sets document-related variables once based on the current document
 * @param {Element|Object} [doc] An element or document object to use to set the document
 * @returns {Object} Returns the current document
 */
setDocument = Sizzle.setDocument = function( node ) {
	var hasCompare, subWindow,
		doc = node ? node.ownerDocument || node : preferredDoc;

	// Return early if doc is invalid or already selected
	// Support: IE 11+, Edge 17 - 18+
	// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
	// two documents; shallow comparisons work.
	// eslint-disable-next-line eqeqeq
	if ( doc == document || doc.nodeType !== 9 || !doc.documentElement ) {
		return document;
	}

	// Update global variables
	document = doc;
	docElem = document.documentElement;
	documentIsHTML = !isXML( document );

	// Support: IE 9 - 11+, Edge 12 - 18+
	// Accessing iframe documents after unload throws "permission denied" errors (jQuery #13936)
	// Support: IE 11+, Edge 17 - 18+
	// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
	// two documents; shallow comparisons work.
	// eslint-disable-next-line eqeqeq
	if ( preferredDoc != document &&
		( subWindow = document.defaultView ) && subWindow.top !== subWindow ) {

		// Support: IE 11, Edge
		if ( subWindow.addEventListener ) {
			subWindow.addEventListener( "unload", unloadHandler, false );

		// Support: IE 9 - 10 only
		} else if ( subWindow.attachEvent ) {
			subWindow.attachEvent( "onunload", unloadHandler );
		}
	}

	// Support: IE 8 - 11+, Edge 12 - 18+, Chrome <=16 - 25 only, Firefox <=3.6 - 31 only,
	// Safari 4 - 5 only, Opera <=11.6 - 12.x only
	// IE/Edge & older browsers don't support the :scope pseudo-class.
	// Support: Safari 6.0 only
	// Safari 6.0 supports :scope but it's an alias of :root there.
	support.scope = assert( function( el ) {
		docElem.appendChild( el ).appendChild( document.createElement( "div" ) );
		return typeof el.querySelectorAll !== "undefined" &&
			!el.querySelectorAll( ":scope fieldset div" ).length;
	} );

	/* Attributes
	---------------------------------------------------------------------- */

	// Support: IE<8
	// Verify that getAttribute really returns attributes and not properties
	// (excepting IE8 booleans)
	support.attributes = assert( function( el ) {
		el.className = "i";
		return !el.getAttribute( "className" );
	} );

	/* getElement(s)By*
	---------------------------------------------------------------------- */

	// Check if getElementsByTagName("*") returns only elements
	support.getElementsByTagName = assert( function( el ) {
		el.appendChild( document.createComment( "" ) );
		return !el.getElementsByTagName( "*" ).length;
	} );

	// Support: IE<9
	support.getElementsByClassName = rnative.test( document.getElementsByClassName );

	// Support: IE<10
	// Check if getElementById returns elements by name
	// The broken getElementById methods don't pick up programmatically-set names,
	// so use a roundabout getElementsByName test
	support.getById = assert( function( el ) {
		docElem.appendChild( el ).id = expando;
		return !document.getElementsByName || !document.getElementsByName( expando ).length;
	} );

	// ID filter and find
	if ( support.getById ) {
		Expr.filter[ "ID" ] = function( id ) {
			var attrId = id.replace( runescape, funescape );
			return function( elem ) {
				return elem.getAttribute( "id" ) === attrId;
			};
		};
		Expr.find[ "ID" ] = function( id, context ) {
			if ( typeof context.getElementById !== "undefined" && documentIsHTML ) {
				var elem = context.getElementById( id );
				return elem ? [ elem ] : [];
			}
		};
	} else {
		Expr.filter[ "ID" ] =  function( id ) {
			var attrId = id.replace( runescape, funescape );
			return function( elem ) {
				var node = typeof elem.getAttributeNode !== "undefined" &&
					elem.getAttributeNode( "id" );
				return node && node.value === attrId;
			};
		};

		// Support: IE 6 - 7 only
		// getElementById is not reliable as a find shortcut
		Expr.find[ "ID" ] = function( id, context ) {
			if ( typeof context.getElementById !== "undefined" && documentIsHTML ) {
				var node, i, elems,
					elem = context.getElementById( id );

				if ( elem ) {

					// Verify the id attribute
					node = elem.getAttributeNode( "id" );
					if ( node && node.value === id ) {
						return [ elem ];
					}

					// Fall back on getElementsByName
					elems = context.getElementsByName( id );
					i = 0;
					while ( ( elem = elems[ i++ ] ) ) {
						node = elem.getAttributeNode( "id" );
						if ( node && node.value === id ) {
							return [ elem ];
						}
					}
				}

				return [];
			}
		};
	}

	// Tag
	Expr.find[ "TAG" ] = support.getElementsByTagName ?
		function( tag, context ) {
			if ( typeof context.getElementsByTagName !== "undefined" ) {
				return context.getElementsByTagName( tag );

			// DocumentFragment nodes don't have gEBTN
			} else if ( support.qsa ) {
				return context.querySelectorAll( tag );
			}
		} :

		function( tag, context ) {
			var elem,
				tmp = [],
				i = 0,

				// By happy coincidence, a (broken) gEBTN appears on DocumentFragment nodes too
				results = context.getElementsByTagName( tag );

			// Filter out possible comments
			if ( tag === "*" ) {
				while ( ( elem = results[ i++ ] ) ) {
					if ( elem.nodeType === 1 ) {
						tmp.push( elem );
					}
				}

				return tmp;
			}
			return results;
		};

	// Class
	Expr.find[ "CLASS" ] = support.getElementsByClassName && function( className, context ) {
		if ( typeof context.getElementsByClassName !== "undefined" && documentIsHTML ) {
			return context.getElementsByClassName( className );
		}
	};

	/* QSA/matchesSelector
	---------------------------------------------------------------------- */

	// QSA and matchesSelector support

	// matchesSelector(:active) reports false when true (IE9/Opera 11.5)
	rbuggyMatches = [];

	// qSa(:focus) reports false when true (Chrome 21)
	// We allow this because of a bug in IE8/9 that throws an error
	// whenever `document.activeElement` is accessed on an iframe
	// So, we allow :focus to pass through QSA all the time to avoid the IE error
	// See https://bugs.jquery.com/ticket/13378
	rbuggyQSA = [];

	if ( ( support.qsa = rnative.test( document.querySelectorAll ) ) ) {

		// Build QSA regex
		// Regex strategy adopted from Diego Perini
		assert( function( el ) {

			var input;

			// Select is set to empty string on purpose
			// This is to test IE's treatment of not explicitly
			// setting a boolean content attribute,
			// since its presence should be enough
			// https://bugs.jquery.com/ticket/12359
			docElem.appendChild( el ).innerHTML = "<a id='" + expando + "'></a>" +
				"<select id='" + expando + "-\r\\' msallowcapture=''>" +
				"<option selected=''></option></select>";

			// Support: IE8, Opera 11-12.16
			// Nothing should be selected when empty strings follow ^= or $= or *=
			// The test attribute must be unknown in Opera but "safe" for WinRT
			// https://msdn.microsoft.com/en-us/library/ie/hh465388.aspx#attribute_section
			if ( el.querySelectorAll( "[msallowcapture^='']" ).length ) {
				rbuggyQSA.push( "[*^$]=" + whitespace + "*(?:''|\"\")" );
			}

			// Support: IE8
			// Boolean attributes and "value" are not treated correctly
			if ( !el.querySelectorAll( "[selected]" ).length ) {
				rbuggyQSA.push( "\\[" + whitespace + "*(?:value|" + booleans + ")" );
			}

			// Support: Chrome<29, Android<4.4, Safari<7.0+, iOS<7.0+, PhantomJS<1.9.8+
			if ( !el.querySelectorAll( "[id~=" + expando + "-]" ).length ) {
				rbuggyQSA.push( "~=" );
			}

			// Support: IE 11+, Edge 15 - 18+
			// IE 11/Edge don't find elements on a `[name='']` query in some cases.
			// Adding a temporary attribute to the document before the selection works
			// around the issue.
			// Interestingly, IE 10 & older don't seem to have the issue.
			input = document.createElement( "input" );
			input.setAttribute( "name", "" );
			el.appendChild( input );
			if ( !el.querySelectorAll( "[name='']" ).length ) {
				rbuggyQSA.push( "\\[" + whitespace + "*name" + whitespace + "*=" +
					whitespace + "*(?:''|\"\")" );
			}

			// Webkit/Opera - :checked should return selected option elements
			// http://www.w3.org/TR/2011/REC-css3-selectors-20110929/#checked
			// IE8 throws error here and will not see later tests
			if ( !el.querySelectorAll( ":checked" ).length ) {
				rbuggyQSA.push( ":checked" );
			}

			// Support: Safari 8+, iOS 8+
			// https://bugs.webkit.org/show_bug.cgi?id=136851
			// In-page `selector#id sibling-combinator selector` fails
			if ( !el.querySelectorAll( "a#" + expando + "+*" ).length ) {
				rbuggyQSA.push( ".#.+[+~]" );
			}

			// Support: Firefox <=3.6 - 5 only
			// Old Firefox doesn't throw on a badly-escaped identifier.
			el.querySelectorAll( "\\\f" );
			rbuggyQSA.push( "[\\r\\n\\f]" );
		} );

		assert( function( el ) {
			el.innerHTML = "<a href='' disabled='disabled'></a>" +
				"<select disabled='disabled'><option/></select>";

			// Support: Windows 8 Native Apps
			// The type and name attributes are restricted during .innerHTML assignment
			var input = document.createElement( "input" );
			input.setAttribute( "type", "hidden" );
			el.appendChild( input ).setAttribute( "name", "D" );

			// Support: IE8
			// Enforce case-sensitivity of name attribute
			if ( el.querySelectorAll( "[name=d]" ).length ) {
				rbuggyQSA.push( "name" + whitespace + "*[*^$|!~]?=" );
			}

			// FF 3.5 - :enabled/:disabled and hidden elements (hidden elements are still enabled)
			// IE8 throws error here and will not see later tests
			if ( el.querySelectorAll( ":enabled" ).length !== 2 ) {
				rbuggyQSA.push( ":enabled", ":disabled" );
			}

			// Support: IE9-11+
			// IE's :disabled selector does not pick up the children of disabled fieldsets
			docElem.appendChild( el ).disabled = true;
			if ( el.querySelectorAll( ":disabled" ).length !== 2 ) {
				rbuggyQSA.push( ":enabled", ":disabled" );
			}

			// Support: Opera 10 - 11 only
			// Opera 10-11 does not throw on post-comma invalid pseudos
			el.querySelectorAll( "*,:x" );
			rbuggyQSA.push( ",.*:" );
		} );
	}

	if ( ( support.matchesSelector = rnative.test( ( matches = docElem.matches ||
		docElem.webkitMatchesSelector ||
		docElem.mozMatchesSelector ||
		docElem.oMatchesSelector ||
		docElem.msMatchesSelector ) ) ) ) {

		assert( function( el ) {

			// Check to see if it's possible to do matchesSelector
			// on a disconnected node (IE 9)
			support.disconnectedMatch = matches.call( el, "*" );

			// This should fail with an exception
			// Gecko does not error, returns false instead
			matches.call( el, "[s!='']:x" );
			rbuggyMatches.push( "!=", pseudos );
		} );
	}

	rbuggyQSA = rbuggyQSA.length && new RegExp( rbuggyQSA.join( "|" ) );
	rbuggyMatches = rbuggyMatches.length && new RegExp( rbuggyMatches.join( "|" ) );

	/* Contains
	---------------------------------------------------------------------- */
	hasCompare = rnative.test( docElem.compareDocumentPosition );

	// Element contains another
	// Purposefully self-exclusive
	// As in, an element does not contain itself
	contains = hasCompare || rnative.test( docElem.contains ) ?
		function( a, b ) {
			var adown = a.nodeType === 9 ? a.documentElement : a,
				bup = b && b.parentNode;
			return a === bup || !!( bup && bup.nodeType === 1 && (
				adown.contains ?
					adown.contains( bup ) :
					a.compareDocumentPosition && a.compareDocumentPosition( bup ) & 16
			) );
		} :
		function( a, b ) {
			if ( b ) {
				while ( ( b = b.parentNode ) ) {
					if ( b === a ) {
						return true;
					}
				}
			}
			return false;
		};

	/* Sorting
	---------------------------------------------------------------------- */

	// Document order sorting
	sortOrder = hasCompare ?
	function( a, b ) {

		// Flag for duplicate removal
		if ( a === b ) {
			hasDuplicate = true;
			return 0;
		}

		// Sort on method existence if only one input has compareDocumentPosition
		var compare = !a.compareDocumentPosition - !b.compareDocumentPosition;
		if ( compare ) {
			return compare;
		}

		// Calculate position if both inputs belong to the same document
		// Support: IE 11+, Edge 17 - 18+
		// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
		// two documents; shallow comparisons work.
		// eslint-disable-next-line eqeqeq
		compare = ( a.ownerDocument || a ) == ( b.ownerDocument || b ) ?
			a.compareDocumentPosition( b ) :

			// Otherwise we know they are disconnected
			1;

		// Disconnected nodes
		if ( compare & 1 ||
			( !support.sortDetached && b.compareDocumentPosition( a ) === compare ) ) {

			// Choose the first element that is related to our preferred document
			// Support: IE 11+, Edge 17 - 18+
			// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
			// two documents; shallow comparisons work.
			// eslint-disable-next-line eqeqeq
			if ( a == document || a.ownerDocument == preferredDoc &&
				contains( preferredDoc, a ) ) {
				return -1;
			}

			// Support: IE 11+, Edge 17 - 18+
			// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
			// two documents; shallow comparisons work.
			// eslint-disable-next-line eqeqeq
			if ( b == document || b.ownerDocument == preferredDoc &&
				contains( preferredDoc, b ) ) {
				return 1;
			}

			// Maintain original order
			return sortInput ?
				( indexOf( sortInput, a ) - indexOf( sortInput, b ) ) :
				0;
		}

		return compare & 4 ? -1 : 1;
	} :
	function( a, b ) {

		// Exit early if the nodes are identical
		if ( a === b ) {
			hasDuplicate = true;
			return 0;
		}

		var cur,
			i = 0,
			aup = a.parentNode,
			bup = b.parentNode,
			ap = [ a ],
			bp = [ b ];

		// Parentless nodes are either documents or disconnected
		if ( !aup || !bup ) {

			// Support: IE 11+, Edge 17 - 18+
			// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
			// two documents; shallow comparisons work.
			/* eslint-disable eqeqeq */
			return a == document ? -1 :
				b == document ? 1 :
				/* eslint-enable eqeqeq */
				aup ? -1 :
				bup ? 1 :
				sortInput ?
				( indexOf( sortInput, a ) - indexOf( sortInput, b ) ) :
				0;

		// If the nodes are siblings, we can do a quick check
		} else if ( aup === bup ) {
			return siblingCheck( a, b );
		}

		// Otherwise we need full lists of their ancestors for comparison
		cur = a;
		while ( ( cur = cur.parentNode ) ) {
			ap.unshift( cur );
		}
		cur = b;
		while ( ( cur = cur.parentNode ) ) {
			bp.unshift( cur );
		}

		// Walk down the tree looking for a discrepancy
		while ( ap[ i ] === bp[ i ] ) {
			i++;
		}

		return i ?

			// Do a sibling check if the nodes have a common ancestor
			siblingCheck( ap[ i ], bp[ i ] ) :

			// Otherwise nodes in our document sort first
			// Support: IE 11+, Edge 17 - 18+
			// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
			// two documents; shallow comparisons work.
			/* eslint-disable eqeqeq */
			ap[ i ] == preferredDoc ? -1 :
			bp[ i ] == preferredDoc ? 1 :
			/* eslint-enable eqeqeq */
			0;
	};

	return document;
};

Sizzle.matches = function( expr, elements ) {
	return Sizzle( expr, null, null, elements );
};

Sizzle.matchesSelector = function( elem, expr ) {
	setDocument( elem );

	if ( support.matchesSelector && documentIsHTML &&
		!nonnativeSelectorCache[ expr + " " ] &&
		( !rbuggyMatches || !rbuggyMatches.test( expr ) ) &&
		( !rbuggyQSA     || !rbuggyQSA.test( expr ) ) ) {

		try {
			var ret = matches.call( elem, expr );

			// IE 9's matchesSelector returns false on disconnected nodes
			if ( ret || support.disconnectedMatch ||

				// As well, disconnected nodes are said to be in a document
				// fragment in IE 9
				elem.document && elem.document.nodeType !== 11 ) {
				return ret;
			}
		} catch ( e ) {
			nonnativeSelectorCache( expr, true );
		}
	}

	return Sizzle( expr, document, null, [ elem ] ).length > 0;
};

Sizzle.contains = function( context, elem ) {

	// Set document vars if needed
	// Support: IE 11+, Edge 17 - 18+
	// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
	// two documents; shallow comparisons work.
	// eslint-disable-next-line eqeqeq
	if ( ( context.ownerDocument || context ) != document ) {
		setDocument( context );
	}
	return contains( context, elem );
};

Sizzle.attr = function( elem, name ) {

	// Set document vars if needed
	// Support: IE 11+, Edge 17 - 18+
	// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
	// two documents; shallow comparisons work.
	// eslint-disable-next-line eqeqeq
	if ( ( elem.ownerDocument || elem ) != document ) {
		setDocument( elem );
	}

	var fn = Expr.attrHandle[ name.toLowerCase() ],

		// Don't get fooled by Object.prototype properties (jQuery #13807)
		val = fn && hasOwn.call( Expr.attrHandle, name.toLowerCase() ) ?
			fn( elem, name, !documentIsHTML ) :
			undefined;

	return val !== undefined ?
		val :
		support.attributes || !documentIsHTML ?
			elem.getAttribute( name ) :
			( val = elem.getAttributeNode( name ) ) && val.specified ?
				val.value :
				null;
};

Sizzle.escape = function( sel ) {
	return ( sel + "" ).replace( rcssescape, fcssescape );
};

Sizzle.error = function( msg ) {
	throw new Error( "Syntax error, unrecognized expression: " + msg );
};

/**
 * Document sorting and removing duplicates
 * @param {ArrayLike} results
 */
Sizzle.uniqueSort = function( results ) {
	var elem,
		duplicates = [],
		j = 0,
		i = 0;

	// Unless we *know* we can detect duplicates, assume their presence
	hasDuplicate = !support.detectDuplicates;
	sortInput = !support.sortStable && results.slice( 0 );
	results.sort( sortOrder );

	if ( hasDuplicate ) {
		while ( ( elem = results[ i++ ] ) ) {
			if ( elem === results[ i ] ) {
				j = duplicates.push( i );
			}
		}
		while ( j-- ) {
			results.splice( duplicates[ j ], 1 );
		}
	}

	// Clear input after sorting to release objects
	// See https://github.com/jquery/sizzle/pull/225
	sortInput = null;

	return results;
};

/**
 * Utility function for retrieving the text value of an array of DOM nodes
 * @param {Array|Element} elem
 */
getText = Sizzle.getText = function( elem ) {
	var node,
		ret = "",
		i = 0,
		nodeType = elem.nodeType;

	if ( !nodeType ) {

		// If no nodeType, this is expected to be an array
		while ( ( node = elem[ i++ ] ) ) {

			// Do not traverse comment nodes
			ret += getText( node );
		}
	} else if ( nodeType === 1 || nodeType === 9 || nodeType === 11 ) {

		// Use textContent for elements
		// innerText usage removed for consistency of new lines (jQuery #11153)
		if ( typeof elem.textContent === "string" ) {
			return elem.textContent;
		} else {

			// Traverse its children
			for ( elem = elem.firstChild; elem; elem = elem.nextSibling ) {
				ret += getText( elem );
			}
		}
	} else if ( nodeType === 3 || nodeType === 4 ) {
		return elem.nodeValue;
	}

	// Do not include comment or processing instruction nodes

	return ret;
};

Expr = Sizzle.selectors = {

	// Can be adjusted by the user
	cacheLength: 50,

	createPseudo: markFunction,

	match: matchExpr,

	attrHandle: {},

	find: {},

	relative: {
		">": { dir: "parentNode", first: true },
		" ": { dir: "parentNode" },
		"+": { dir: "previousSibling", first: true },
		"~": { dir: "previousSibling" }
	},

	preFilter: {
		"ATTR": function( match ) {
			match[ 1 ] = match[ 1 ].replace( runescape, funescape );

			// Move the given value to match[3] whether quoted or unquoted
			match[ 3 ] = ( match[ 3 ] || match[ 4 ] ||
				match[ 5 ] || "" ).replace( runescape, funescape );

			if ( match[ 2 ] === "~=" ) {
				match[ 3 ] = " " + match[ 3 ] + " ";
			}

			return match.slice( 0, 4 );
		},

		"CHILD": function( match ) {

			/* matches from matchExpr["CHILD"]
				1 type (only|nth|...)
				2 what (child|of-type)
				3 argument (even|odd|\d*|\d*n([+-]\d+)?|...)
				4 xn-component of xn+y argument ([+-]?\d*n|)
				5 sign of xn-component
				6 x of xn-component
				7 sign of y-component
				8 y of y-component
			*/
			match[ 1 ] = match[ 1 ].toLowerCase();

			if ( match[ 1 ].slice( 0, 3 ) === "nth" ) {

				// nth-* requires argument
				if ( !match[ 3 ] ) {
					Sizzle.error( match[ 0 ] );
				}

				// numeric x and y parameters for Expr.filter.CHILD
				// remember that false/true cast respectively to 0/1
				match[ 4 ] = +( match[ 4 ] ?
					match[ 5 ] + ( match[ 6 ] || 1 ) :
					2 * ( match[ 3 ] === "even" || match[ 3 ] === "odd" ) );
				match[ 5 ] = +( ( match[ 7 ] + match[ 8 ] ) || match[ 3 ] === "odd" );

				// other types prohibit arguments
			} else if ( match[ 3 ] ) {
				Sizzle.error( match[ 0 ] );
			}

			return match;
		},

		"PSEUDO": function( match ) {
			var excess,
				unquoted = !match[ 6 ] && match[ 2 ];

			if ( matchExpr[ "CHILD" ].test( match[ 0 ] ) ) {
				return null;
			}

			// Accept quoted arguments as-is
			if ( match[ 3 ] ) {
				match[ 2 ] = match[ 4 ] || match[ 5 ] || "";

			// Strip excess characters from unquoted arguments
			} else if ( unquoted && rpseudo.test( unquoted ) &&

				// Get excess from tokenize (recursively)
				( excess = tokenize( unquoted, true ) ) &&

				// advance to the next closing parenthesis
				( excess = unquoted.indexOf( ")", unquoted.length - excess ) - unquoted.length ) ) {

				// excess is a negative index
				match[ 0 ] = match[ 0 ].slice( 0, excess );
				match[ 2 ] = unquoted.slice( 0, excess );
			}

			// Return only captures needed by the pseudo filter method (type and argument)
			return match.slice( 0, 3 );
		}
	},

	filter: {

		"TAG": function( nodeNameSelector ) {
			var nodeName = nodeNameSelector.replace( runescape, funescape ).toLowerCase();
			return nodeNameSelector === "*" ?
				function() {
					return true;
				} :
				function( elem ) {
					return elem.nodeName && elem.nodeName.toLowerCase() === nodeName;
				};
		},

		"CLASS": function( className ) {
			var pattern = classCache[ className + " " ];

			return pattern ||
				( pattern = new RegExp( "(^|" + whitespace +
					")" + className + "(" + whitespace + "|$)" ) ) && classCache(
						className, function( elem ) {
							return pattern.test(
								typeof elem.className === "string" && elem.className ||
								typeof elem.getAttribute !== "undefined" &&
									elem.getAttribute( "class" ) ||
								""
							);
				} );
		},

		"ATTR": function( name, operator, check ) {
			return function( elem ) {
				var result = Sizzle.attr( elem, name );

				if ( result == null ) {
					return operator === "!=";
				}
				if ( !operator ) {
					return true;
				}

				result += "";

				/* eslint-disable max-len */

				return operator === "=" ? result === check :
					operator === "!=" ? result !== check :
					operator === "^=" ? check && result.indexOf( check ) === 0 :
					operator === "*=" ? check && result.indexOf( check ) > -1 :
					operator === "$=" ? check && result.slice( -check.length ) === check :
					operator === "~=" ? ( " " + result.replace( rwhitespace, " " ) + " " ).indexOf( check ) > -1 :
					operator === "|=" ? result === check || result.slice( 0, check.length + 1 ) === check + "-" :
					false;
				/* eslint-enable max-len */

			};
		},

		"CHILD": function( type, what, _argument, first, last ) {
			var simple = type.slice( 0, 3 ) !== "nth",
				forward = type.slice( -4 ) !== "last",
				ofType = what === "of-type";

			return first === 1 && last === 0 ?

				// Shortcut for :nth-*(n)
				function( elem ) {
					return !!elem.parentNode;
				} :

				function( elem, _context, xml ) {
					var cache, uniqueCache, outerCache, node, nodeIndex, start,
						dir = simple !== forward ? "nextSibling" : "previousSibling",
						parent = elem.parentNode,
						name = ofType && elem.nodeName.toLowerCase(),
						useCache = !xml && !ofType,
						diff = false;

					if ( parent ) {

						// :(first|last|only)-(child|of-type)
						if ( simple ) {
							while ( dir ) {
								node = elem;
								while ( ( node = node[ dir ] ) ) {
									if ( ofType ?
										node.nodeName.toLowerCase() === name :
										node.nodeType === 1 ) {

										return false;
									}
								}

								// Reverse direction for :only-* (if we haven't yet done so)
								start = dir = type === "only" && !start && "nextSibling";
							}
							return true;
						}

						start = [ forward ? parent.firstChild : parent.lastChild ];

						// non-xml :nth-child(...) stores cache data on `parent`
						if ( forward && useCache ) {

							// Seek `elem` from a previously-cached index

							// ...in a gzip-friendly way
							node = parent;
							outerCache = node[ expando ] || ( node[ expando ] = {} );

							// Support: IE <9 only
							// Defend against cloned attroperties (jQuery gh-1709)
							uniqueCache = outerCache[ node.uniqueID ] ||
								( outerCache[ node.uniqueID ] = {} );

							cache = uniqueCache[ type ] || [];
							nodeIndex = cache[ 0 ] === dirruns && cache[ 1 ];
							diff = nodeIndex && cache[ 2 ];
							node = nodeIndex && parent.childNodes[ nodeIndex ];

							while ( ( node = ++nodeIndex && node && node[ dir ] ||

								// Fallback to seeking `elem` from the start
								( diff = nodeIndex = 0 ) || start.pop() ) ) {

								// When found, cache indexes on `parent` and break
								if ( node.nodeType === 1 && ++diff && node === elem ) {
									uniqueCache[ type ] = [ dirruns, nodeIndex, diff ];
									break;
								}
							}

						} else {

							// Use previously-cached element index if available
							if ( useCache ) {

								// ...in a gzip-friendly way
								node = elem;
								outerCache = node[ expando ] || ( node[ expando ] = {} );

								// Support: IE <9 only
								// Defend against cloned attroperties (jQuery gh-1709)
								uniqueCache = outerCache[ node.uniqueID ] ||
									( outerCache[ node.uniqueID ] = {} );

								cache = uniqueCache[ type ] || [];
								nodeIndex = cache[ 0 ] === dirruns && cache[ 1 ];
								diff = nodeIndex;
							}

							// xml :nth-child(...)
							// or :nth-last-child(...) or :nth(-last)?-of-type(...)
							if ( diff === false ) {

								// Use the same loop as above to seek `elem` from the start
								while ( ( node = ++nodeIndex && node && node[ dir ] ||
									( diff = nodeIndex = 0 ) || start.pop() ) ) {

									if ( ( ofType ?
										node.nodeName.toLowerCase() === name :
										node.nodeType === 1 ) &&
										++diff ) {

										// Cache the index of each encountered element
										if ( useCache ) {
											outerCache = node[ expando ] ||
												( node[ expando ] = {} );

											// Support: IE <9 only
											// Defend against cloned attroperties (jQuery gh-1709)
											uniqueCache = outerCache[ node.uniqueID ] ||
												( outerCache[ node.uniqueID ] = {} );

											uniqueCache[ type ] = [ dirruns, diff ];
										}

										if ( node === elem ) {
											break;
										}
									}
								}
							}
						}

						// Incorporate the offset, then check against cycle size
						diff -= last;
						return diff === first || ( diff % first === 0 && diff / first >= 0 );
					}
				};
		},

		"PSEUDO": function( pseudo, argument ) {

			// pseudo-class names are case-insensitive
			// http://www.w3.org/TR/selectors/#pseudo-classes
			// Prioritize by case sensitivity in case custom pseudos are added with uppercase letters
			// Remember that setFilters inherits from pseudos
			var args,
				fn = Expr.pseudos[ pseudo ] || Expr.setFilters[ pseudo.toLowerCase() ] ||
					Sizzle.error( "unsupported pseudo: " + pseudo );

			// The user may use createPseudo to indicate that
			// arguments are needed to create the filter function
			// just as Sizzle does
			if ( fn[ expando ] ) {
				return fn( argument );
			}

			// But maintain support for old signatures
			if ( fn.length > 1 ) {
				args = [ pseudo, pseudo, "", argument ];
				return Expr.setFilters.hasOwnProperty( pseudo.toLowerCase() ) ?
					markFunction( function( seed, matches ) {
						var idx,
							matched = fn( seed, argument ),
							i = matched.length;
						while ( i-- ) {
							idx = indexOf( seed, matched[ i ] );
							seed[ idx ] = !( matches[ idx ] = matched[ i ] );
						}
					} ) :
					function( elem ) {
						return fn( elem, 0, args );
					};
			}

			return fn;
		}
	},

	pseudos: {

		// Potentially complex pseudos
		"not": markFunction( function( selector ) {

			// Trim the selector passed to compile
			// to avoid treating leading and trailing
			// spaces as combinators
			var input = [],
				results = [],
				matcher = compile( selector.replace( rtrim, "$1" ) );

			return matcher[ expando ] ?
				markFunction( function( seed, matches, _context, xml ) {
					var elem,
						unmatched = matcher( seed, null, xml, [] ),
						i = seed.length;

					// Match elements unmatched by `matcher`
					while ( i-- ) {
						if ( ( elem = unmatched[ i ] ) ) {
							seed[ i ] = !( matches[ i ] = elem );
						}
					}
				} ) :
				function( elem, _context, xml ) {
					input[ 0 ] = elem;
					matcher( input, null, xml, results );

					// Don't keep the element (issue #299)
					input[ 0 ] = null;
					return !results.pop();
				};
		} ),

		"has": markFunction( function( selector ) {
			return function( elem ) {
				return Sizzle( selector, elem ).length > 0;
			};
		} ),

		"contains": markFunction( function( text ) {
			text = text.replace( runescape, funescape );
			return function( elem ) {
				return ( elem.textContent || getText( elem ) ).indexOf( text ) > -1;
			};
		} ),

		// "Whether an element is represented by a :lang() selector
		// is based solely on the element's language value
		// being equal to the identifier C,
		// or beginning with the identifier C immediately followed by "-".
		// The matching of C against the element's language value is performed case-insensitively.
		// The identifier C does not have to be a valid language name."
		// http://www.w3.org/TR/selectors/#lang-pseudo
		"lang": markFunction( function( lang ) {

			// lang value must be a valid identifier
			if ( !ridentifier.test( lang || "" ) ) {
				Sizzle.error( "unsupported lang: " + lang );
			}
			lang = lang.replace( runescape, funescape ).toLowerCase();
			return function( elem ) {
				var elemLang;
				do {
					if ( ( elemLang = documentIsHTML ?
						elem.lang :
						elem.getAttribute( "xml:lang" ) || elem.getAttribute( "lang" ) ) ) {

						elemLang = elemLang.toLowerCase();
						return elemLang === lang || elemLang.indexOf( lang + "-" ) === 0;
					}
				} while ( ( elem = elem.parentNode ) && elem.nodeType === 1 );
				return false;
			};
		} ),

		// Miscellaneous
		"target": function( elem ) {
			var hash = window.location && window.location.hash;
			return hash && hash.slice( 1 ) === elem.id;
		},

		"root": function( elem ) {
			return elem === docElem;
		},

		"focus": function( elem ) {
			return elem === document.activeElement &&
				( !document.hasFocus || document.hasFocus() ) &&
				!!( elem.type || elem.href || ~elem.tabIndex );
		},

		// Boolean properties
		"enabled": createDisabledPseudo( false ),
		"disabled": createDisabledPseudo( true ),

		"checked": function( elem ) {

			// In CSS3, :checked should return both checked and selected elements
			// http://www.w3.org/TR/2011/REC-css3-selectors-20110929/#checked
			var nodeName = elem.nodeName.toLowerCase();
			return ( nodeName === "input" && !!elem.checked ) ||
				( nodeName === "option" && !!elem.selected );
		},

		"selected": function( elem ) {

			// Accessing this property makes selected-by-default
			// options in Safari work properly
			if ( elem.parentNode ) {
				// eslint-disable-next-line no-unused-expressions
				elem.parentNode.selectedIndex;
			}

			return elem.selected === true;
		},

		// Contents
		"empty": function( elem ) {

			// http://www.w3.org/TR/selectors/#empty-pseudo
			// :empty is negated by element (1) or content nodes (text: 3; cdata: 4; entity ref: 5),
			//   but not by others (comment: 8; processing instruction: 7; etc.)
			// nodeType < 6 works because attributes (2) do not appear as children
			for ( elem = elem.firstChild; elem; elem = elem.nextSibling ) {
				if ( elem.nodeType < 6 ) {
					return false;
				}
			}
			return true;
		},

		"parent": function( elem ) {
			return !Expr.pseudos[ "empty" ]( elem );
		},

		// Element/input types
		"header": function( elem ) {
			return rheader.test( elem.nodeName );
		},

		"input": function( elem ) {
			return rinputs.test( elem.nodeName );
		},

		"button": function( elem ) {
			var name = elem.nodeName.toLowerCase();
			return name === "input" && elem.type === "button" || name === "button";
		},

		"text": function( elem ) {
			var attr;
			return elem.nodeName.toLowerCase() === "input" &&
				elem.type === "text" &&

				// Support: IE<8
				// New HTML5 attribute values (e.g., "search") appear with elem.type === "text"
				( ( attr = elem.getAttribute( "type" ) ) == null ||
					attr.toLowerCase() === "text" );
		},

		// Position-in-collection
		"first": createPositionalPseudo( function() {
			return [ 0 ];
		} ),

		"last": createPositionalPseudo( function( _matchIndexes, length ) {
			return [ length - 1 ];
		} ),

		"eq": createPositionalPseudo( function( _matchIndexes, length, argument ) {
			return [ argument < 0 ? argument + length : argument ];
		} ),

		"even": createPositionalPseudo( function( matchIndexes, length ) {
			var i = 0;
			for ( ; i < length; i += 2 ) {
				matchIndexes.push( i );
			}
			return matchIndexes;
		} ),

		"odd": createPositionalPseudo( function( matchIndexes, length ) {
			var i = 1;
			for ( ; i < length; i += 2 ) {
				matchIndexes.push( i );
			}
			return matchIndexes;
		} ),

		"lt": createPositionalPseudo( function( matchIndexes, length, argument ) {
			var i = argument < 0 ?
				argument + length :
				argument > length ?
					length :
					argument;
			for ( ; --i >= 0; ) {
				matchIndexes.push( i );
			}
			return matchIndexes;
		} ),

		"gt": createPositionalPseudo( function( matchIndexes, length, argument ) {
			var i = argument < 0 ? argument + length : argument;
			for ( ; ++i < length; ) {
				matchIndexes.push( i );
			}
			return matchIndexes;
		} )
	}
};

Expr.pseudos[ "nth" ] = Expr.pseudos[ "eq" ];

// Add button/input type pseudos
for ( i in { radio: true, checkbox: true, file: true, password: true, image: true } ) {
	Expr.pseudos[ i ] = createInputPseudo( i );
}
for ( i in { submit: true, reset: true } ) {
	Expr.pseudos[ i ] = createButtonPseudo( i );
}

// Easy API for creating new setFilters
function setFilters() {}
setFilters.prototype = Expr.filters = Expr.pseudos;
Expr.setFilters = new setFilters();

tokenize = Sizzle.tokenize = function( selector, parseOnly ) {
	var matched, match, tokens, type,
		soFar, groups, preFilters,
		cached = tokenCache[ selector + " " ];

	if ( cached ) {
		return parseOnly ? 0 : cached.slice( 0 );
	}

	soFar = selector;
	groups = [];
	preFilters = Expr.preFilter;

	while ( soFar ) {

		// Comma and first run
		if ( !matched || ( match = rcomma.exec( soFar ) ) ) {
			if ( match ) {

				// Don't consume trailing commas as valid
				soFar = soFar.slice( match[ 0 ].length ) || soFar;
			}
			groups.push( ( tokens = [] ) );
		}

		matched = false;

		// Combinators
		if ( ( match = rcombinators.exec( soFar ) ) ) {
			matched = match.shift();
			tokens.push( {
				value: matched,

				// Cast descendant combinators to space
				type: match[ 0 ].replace( rtrim, " " )
			} );
			soFar = soFar.slice( matched.length );
		}

		// Filters
		for ( type in Expr.filter ) {
			if ( ( match = matchExpr[ type ].exec( soFar ) ) && ( !preFilters[ type ] ||
				( match = preFilters[ type ]( match ) ) ) ) {
				matched = match.shift();
				tokens.push( {
					value: matched,
					type: type,
					matches: match
				} );
				soFar = soFar.slice( matched.length );
			}
		}

		if ( !matched ) {
			break;
		}
	}

	// Return the length of the invalid excess
	// if we're just parsing
	// Otherwise, throw an error or return tokens
	return parseOnly ?
		soFar.length :
		soFar ?
			Sizzle.error( selector ) :

			// Cache the tokens
			tokenCache( selector, groups ).slice( 0 );
};

function toSelector( tokens ) {
	var i = 0,
		len = tokens.length,
		selector = "";
	for ( ; i < len; i++ ) {
		selector += tokens[ i ].value;
	}
	return selector;
}

function addCombinator( matcher, combinator, base ) {
	var dir = combinator.dir,
		skip = combinator.next,
		key = skip || dir,
		checkNonElements = base && key === "parentNode",
		doneName = done++;

	return combinator.first ?

		// Check against closest ancestor/preceding element
		function( elem, context, xml ) {
			while ( ( elem = elem[ dir ] ) ) {
				if ( elem.nodeType === 1 || checkNonElements ) {
					return matcher( elem, context, xml );
				}
			}
			return false;
		} :

		// Check against all ancestor/preceding elements
		function( elem, context, xml ) {
			var oldCache, uniqueCache, outerCache,
				newCache = [ dirruns, doneName ];

			// We can't set arbitrary data on XML nodes, so they don't benefit from combinator caching
			if ( xml ) {
				while ( ( elem = elem[ dir ] ) ) {
					if ( elem.nodeType === 1 || checkNonElements ) {
						if ( matcher( elem, context, xml ) ) {
							return true;
						}
					}
				}
			} else {
				while ( ( elem = elem[ dir ] ) ) {
					if ( elem.nodeType === 1 || checkNonElements ) {
						outerCache = elem[ expando ] || ( elem[ expando ] = {} );

						// Support: IE <9 only
						// Defend against cloned attroperties (jQuery gh-1709)
						uniqueCache = outerCache[ elem.uniqueID ] ||
							( outerCache[ elem.uniqueID ] = {} );

						if ( skip && skip === elem.nodeName.toLowerCase() ) {
							elem = elem[ dir ] || elem;
						} else if ( ( oldCache = uniqueCache[ key ] ) &&
							oldCache[ 0 ] === dirruns && oldCache[ 1 ] === doneName ) {

							// Assign to newCache so results back-propagate to previous elements
							return ( newCache[ 2 ] = oldCache[ 2 ] );
						} else {

							// Reuse newcache so results back-propagate to previous elements
							uniqueCache[ key ] = newCache;

							// A match means we're done; a fail means we have to keep checking
							if ( ( newCache[ 2 ] = matcher( elem, context, xml ) ) ) {
								return true;
							}
						}
					}
				}
			}
			return false;
		};
}

function elementMatcher( matchers ) {
	return matchers.length > 1 ?
		function( elem, context, xml ) {
			var i = matchers.length;
			while ( i-- ) {
				if ( !matchers[ i ]( elem, context, xml ) ) {
					return false;
				}
			}
			return true;
		} :
		matchers[ 0 ];
}

function multipleContexts( selector, contexts, results ) {
	var i = 0,
		len = contexts.length;
	for ( ; i < len; i++ ) {
		Sizzle( selector, contexts[ i ], results );
	}
	return results;
}

function condense( unmatched, map, filter, context, xml ) {
	var elem,
		newUnmatched = [],
		i = 0,
		len = unmatched.length,
		mapped = map != null;

	for ( ; i < len; i++ ) {
		if ( ( elem = unmatched[ i ] ) ) {
			if ( !filter || filter( elem, context, xml ) ) {
				newUnmatched.push( elem );
				if ( mapped ) {
					map.push( i );
				}
			}
		}
	}

	return newUnmatched;
}

function setMatcher( preFilter, selector, matcher, postFilter, postFinder, postSelector ) {
	if ( postFilter && !postFilter[ expando ] ) {
		postFilter = setMatcher( postFilter );
	}
	if ( postFinder && !postFinder[ expando ] ) {
		postFinder = setMatcher( postFinder, postSelector );
	}
	return markFunction( function( seed, results, context, xml ) {
		var temp, i, elem,
			preMap = [],
			postMap = [],
			preexisting = results.length,

			// Get initial elements from seed or context
			elems = seed || multipleContexts(
				selector || "*",
				context.nodeType ? [ context ] : context,
				[]
			),

			// Prefilter to get matcher input, preserving a map for seed-results synchronization
			matcherIn = preFilter && ( seed || !selector ) ?
				condense( elems, preMap, preFilter, context, xml ) :
				elems,

			matcherOut = matcher ?

				// If we have a postFinder, or filtered seed, or non-seed postFilter or preexisting results,
				postFinder || ( seed ? preFilter : preexisting || postFilter ) ?

					// ...intermediate processing is necessary
					[] :

					// ...otherwise use results directly
					results :
				matcherIn;

		// Find primary matches
		if ( matcher ) {
			matcher( matcherIn, matcherOut, context, xml );
		}

		// Apply postFilter
		if ( postFilter ) {
			temp = condense( matcherOut, postMap );
			postFilter( temp, [], context, xml );

			// Un-match failing elements by moving them back to matcherIn
			i = temp.length;
			while ( i-- ) {
				if ( ( elem = temp[ i ] ) ) {
					matcherOut[ postMap[ i ] ] = !( matcherIn[ postMap[ i ] ] = elem );
				}
			}
		}

		if ( seed ) {
			if ( postFinder || preFilter ) {
				if ( postFinder ) {

					// Get the final matcherOut by condensing this intermediate into postFinder contexts
					temp = [];
					i = matcherOut.length;
					while ( i-- ) {
						if ( ( elem = matcherOut[ i ] ) ) {

							// Restore matcherIn since elem is not yet a final match
							temp.push( ( matcherIn[ i ] = elem ) );
						}
					}
					postFinder( null, ( matcherOut = [] ), temp, xml );
				}

				// Move matched elements from seed to results to keep them synchronized
				i = matcherOut.length;
				while ( i-- ) {
					if ( ( elem = matcherOut[ i ] ) &&
						( temp = postFinder ? indexOf( seed, elem ) : preMap[ i ] ) > -1 ) {

						seed[ temp ] = !( results[ temp ] = elem );
					}
				}
			}

		// Add elements to results, through postFinder if defined
		} else {
			matcherOut = condense(
				matcherOut === results ?
					matcherOut.splice( preexisting, matcherOut.length ) :
					matcherOut
			);
			if ( postFinder ) {
				postFinder( null, results, matcherOut, xml );
			} else {
				push.apply( results, matcherOut );
			}
		}
	} );
}

function matcherFromTokens( tokens ) {
	var checkContext, matcher, j,
		len = tokens.length,
		leadingRelative = Expr.relative[ tokens[ 0 ].type ],
		implicitRelative = leadingRelative || Expr.relative[ " " ],
		i = leadingRelative ? 1 : 0,

		// The foundational matcher ensures that elements are reachable from top-level context(s)
		matchContext = addCombinator( function( elem ) {
			return elem === checkContext;
		}, implicitRelative, true ),
		matchAnyContext = addCombinator( function( elem ) {
			return indexOf( checkContext, elem ) > -1;
		}, implicitRelative, true ),
		matchers = [ function( elem, context, xml ) {
			var ret = ( !leadingRelative && ( xml || context !== outermostContext ) ) || (
				( checkContext = context ).nodeType ?
					matchContext( elem, context, xml ) :
					matchAnyContext( elem, context, xml ) );

			// Avoid hanging onto element (issue #299)
			checkContext = null;
			return ret;
		} ];

	for ( ; i < len; i++ ) {
		if ( ( matcher = Expr.relative[ tokens[ i ].type ] ) ) {
			matchers = [ addCombinator( elementMatcher( matchers ), matcher ) ];
		} else {
			matcher = Expr.filter[ tokens[ i ].type ].apply( null, tokens[ i ].matches );

			// Return special upon seeing a positional matcher
			if ( matcher[ expando ] ) {

				// Find the next relative operator (if any) for proper handling
				j = ++i;
				for ( ; j < len; j++ ) {
					if ( Expr.relative[ tokens[ j ].type ] ) {
						break;
					}
				}
				return setMatcher(
					i > 1 && elementMatcher( matchers ),
					i > 1 && toSelector(

					// If the preceding token was a descendant combinator, insert an implicit any-element `*`
					tokens
						.slice( 0, i - 1 )
						.concat( { value: tokens[ i - 2 ].type === " " ? "*" : "" } )
					).replace( rtrim, "$1" ),
					matcher,
					i < j && matcherFromTokens( tokens.slice( i, j ) ),
					j < len && matcherFromTokens( ( tokens = tokens.slice( j ) ) ),
					j < len && toSelector( tokens )
				);
			}
			matchers.push( matcher );
		}
	}

	return elementMatcher( matchers );
}

function matcherFromGroupMatchers( elementMatchers, setMatchers ) {
	var bySet = setMatchers.length > 0,
		byElement = elementMatchers.length > 0,
		superMatcher = function( seed, context, xml, results, outermost ) {
			var elem, j, matcher,
				matchedCount = 0,
				i = "0",
				unmatched = seed && [],
				setMatched = [],
				contextBackup = outermostContext,

				// We must always have either seed elements or outermost context
				elems = seed || byElement && Expr.find[ "TAG" ]( "*", outermost ),

				// Use integer dirruns iff this is the outermost matcher
				dirrunsUnique = ( dirruns += contextBackup == null ? 1 : Math.random() || 0.1 ),
				len = elems.length;

			if ( outermost ) {

				// Support: IE 11+, Edge 17 - 18+
				// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
				// two documents; shallow comparisons work.
				// eslint-disable-next-line eqeqeq
				outermostContext = context == document || context || outermost;
			}

			// Add elements passing elementMatchers directly to results
			// Support: IE<9, Safari
			// Tolerate NodeList properties (IE: "length"; Safari: <number>) matching elements by id
			for ( ; i !== len && ( elem = elems[ i ] ) != null; i++ ) {
				if ( byElement && elem ) {
					j = 0;

					// Support: IE 11+, Edge 17 - 18+
					// IE/Edge sometimes throw a "Permission denied" error when strict-comparing
					// two documents; shallow comparisons work.
					// eslint-disable-next-line eqeqeq
					if ( !context && elem.ownerDocument != document ) {
						setDocument( elem );
						xml = !documentIsHTML;
					}
					while ( ( matcher = elementMatchers[ j++ ] ) ) {
						if ( matcher( elem, context || document, xml ) ) {
							results.push( elem );
							break;
						}
					}
					if ( outermost ) {
						dirruns = dirrunsUnique;
					}
				}

				// Track unmatched elements for set filters
				if ( bySet ) {

					// They will have gone through all possible matchers
					if ( ( elem = !matcher && elem ) ) {
						matchedCount--;
					}

					// Lengthen the array for every element, matched or not
					if ( seed ) {
						unmatched.push( elem );
					}
				}
			}

			// `i` is now the count of elements visited above, and adding it to `matchedCount`
			// makes the latter nonnegative.
			matchedCount += i;

			// Apply set filters to unmatched elements
			// NOTE: This can be skipped if there are no unmatched elements (i.e., `matchedCount`
			// equals `i`), unless we didn't visit _any_ elements in the above loop because we have
			// no element matchers and no seed.
			// Incrementing an initially-string "0" `i` allows `i` to remain a string only in that
			// case, which will result in a "00" `matchedCount` that differs from `i` but is also
			// numerically zero.
			if ( bySet && i !== matchedCount ) {
				j = 0;
				while ( ( matcher = setMatchers[ j++ ] ) ) {
					matcher( unmatched, setMatched, context, xml );
				}

				if ( seed ) {

					// Reintegrate element matches to eliminate the need for sorting
					if ( matchedCount > 0 ) {
						while ( i-- ) {
							if ( !( unmatched[ i ] || setMatched[ i ] ) ) {
								setMatched[ i ] = pop.call( results );
							}
						}
					}

					// Discard index placeholder values to get only actual matches
					setMatched = condense( setMatched );
				}

				// Add matches to results
				push.apply( results, setMatched );

				// Seedless set matches succeeding multiple successful matchers stipulate sorting
				if ( outermost && !seed && setMatched.length > 0 &&
					( matchedCount + setMatchers.length ) > 1 ) {

					Sizzle.uniqueSort( results );
				}
			}

			// Override manipulation of globals by nested matchers
			if ( outermost ) {
				dirruns = dirrunsUnique;
				outermostContext = contextBackup;
			}

			return unmatched;
		};

	return bySet ?
		markFunction( superMatcher ) :
		superMatcher;
}

compile = Sizzle.compile = function( selector, match /* Internal Use Only */ ) {
	var i,
		setMatchers = [],
		elementMatchers = [],
		cached = compilerCache[ selector + " " ];

	if ( !cached ) {

		// Generate a function of recursive functions that can be used to check each element
		if ( !match ) {
			match = tokenize( selector );
		}
		i = match.length;
		while ( i-- ) {
			cached = matcherFromTokens( match[ i ] );
			if ( cached[ expando ] ) {
				setMatchers.push( cached );
			} else {
				elementMatchers.push( cached );
			}
		}

		// Cache the compiled function
		cached = compilerCache(
			selector,
			matcherFromGroupMatchers( elementMatchers, setMatchers )
		);

		// Save selector and tokenization
		cached.selector = selector;
	}
	return cached;
};

/**
 * A low-level selection function that works with Sizzle's compiled
 *  selector functions
 * @param {String|Function} selector A selector or a pre-compiled
 *  selector function built with Sizzle.compile
 * @param {Element} context
 * @param {Array} [results]
 * @param {Array} [seed] A set of elements to match against
 */
select = Sizzle.select = function( selector, context, results, seed ) {
	var i, tokens, token, type, find,
		compiled = typeof selector === "function" && selector,
		match = !seed && tokenize( ( selector = compiled.selector || selector ) );

	results = results || [];

	// Try to minimize operations if there is only one selector in the list and no seed
	// (the latter of which guarantees us context)
	if ( match.length === 1 ) {

		// Reduce context if the leading compound selector is an ID
		tokens = match[ 0 ] = match[ 0 ].slice( 0 );
		if ( tokens.length > 2 && ( token = tokens[ 0 ] ).type === "ID" &&
			context.nodeType === 9 && documentIsHTML && Expr.relative[ tokens[ 1 ].type ] ) {

			context = ( Expr.find[ "ID" ]( token.matches[ 0 ]
				.replace( runescape, funescape ), context ) || [] )[ 0 ];
			if ( !context ) {
				return results;

			// Precompiled matchers will still verify ancestry, so step up a level
			} else if ( compiled ) {
				context = context.parentNode;
			}

			selector = selector.slice( tokens.shift().value.length );
		}

		// Fetch a seed set for right-to-left matching
		i = matchExpr[ "needsContext" ].test( selector ) ? 0 : tokens.length;
		while ( i-- ) {
			token = tokens[ i ];

			// Abort if we hit a combinator
			if ( Expr.relative[ ( type = token.type ) ] ) {
				break;
			}
			if ( ( find = Expr.find[ type ] ) ) {

				// Search, expanding context for leading sibling combinators
				if ( ( seed = find(
					token.matches[ 0 ].replace( runescape, funescape ),
					rsibling.test( tokens[ 0 ].type ) && testContext( context.parentNode ) ||
						context
				) ) ) {

					// If seed is empty or no tokens remain, we can return early
					tokens.splice( i, 1 );
					selector = seed.length && toSelector( tokens );
					if ( !selector ) {
						push.apply( results, seed );
						return results;
					}

					break;
				}
			}
		}
	}

	// Compile and execute a filtering function if one is not provided
	// Provide `match` to avoid retokenization if we modified the selector above
	( compiled || compile( selector, match ) )(
		seed,
		context,
		!documentIsHTML,
		results,
		!context || rsibling.test( selector ) && testContext( context.parentNode ) || context
	);
	return results;
};

// One-time assignments

// Sort stability
support.sortStable = expando.split( "" ).sort( sortOrder ).join( "" ) === expando;

// Support: Chrome 14-35+
// Always assume duplicates if they aren't passed to the comparison function
support.detectDuplicates = !!hasDuplicate;

// Initialize against the default document
setDocument();

// Support: Webkit<537.32 - Safari 6.0.3/Chrome 25 (fixed in Chrome 27)
// Detached nodes confoundingly follow *each other*
support.sortDetached = assert( function( el ) {

	// Should return 1, but returns 4 (following)
	return el.compareDocumentPosition( document.createElement( "fieldset" ) ) & 1;
} );

// Support: IE<8
// Prevent attribute/property "interpolation"
// https://msdn.microsoft.com/en-us/library/ms536429%28VS.85%29.aspx
if ( !assert( function( el ) {
	el.innerHTML = "<a href='#'></a>";
	return el.firstChild.getAttribute( "href" ) === "#";
} ) ) {
	addHandle( "type|href|height|width", function( elem, name, isXML ) {
		if ( !isXML ) {
			return elem.getAttribute( name, name.toLowerCase() === "type" ? 1 : 2 );
		}
	} );
}

// Support: IE<9
// Use defaultValue in place of getAttribute("value")
if ( !support.attributes || !assert( function( el ) {
	el.innerHTML = "<input/>";
	el.firstChild.setAttribute( "value", "" );
	return el.firstChild.getAttribute( "value" ) === "";
} ) ) {
	addHandle( "value", function( elem, _name, isXML ) {
		if ( !isXML && elem.nodeName.toLowerCase() === "input" ) {
			return elem.defaultValue;
		}
	} );
}

// Support: IE<9
// Use getAttributeNode to fetch booleans when getAttribute lies
if ( !assert( function( el ) {
	return el.getAttribute( "disabled" ) == null;
} ) ) {
	addHandle( booleans, function( elem, name, isXML ) {
		var val;
		if ( !isXML ) {
			return elem[ name ] === true ? name.toLowerCase() :
				( val = elem.getAttributeNode( name ) ) && val.specified ?
					val.value :
					null;
		}
	} );
}

return Sizzle;

} )( window );



jQuery.find = Sizzle;
jQuery.expr = Sizzle.selectors;

// Deprecated
jQuery.expr[ ":" ] = jQuery.expr.pseudos;
jQuery.uniqueSort = jQuery.unique = Sizzle.uniqueSort;
jQuery.text = Sizzle.getText;
jQuery.isXMLDoc = Sizzle.isXML;
jQuery.contains = Sizzle.contains;
jQuery.escapeSelector = Sizzle.escape;




var dir = function( elem, dir, until ) {
	var matched = [],
		truncate = until !== undefined;

	while ( ( elem = elem[ dir ] ) && elem.nodeType !== 9 ) {
		if ( elem.nodeType === 1 ) {
			if ( truncate && jQuery( elem ).is( until ) ) {
				break;
			}
			matched.push( elem );
		}
	}
	return matched;
};


var siblings = function( n, elem ) {
	var matched = [];

	for ( ; n; n = n.nextSibling ) {
		if ( n.nodeType === 1 && n !== elem ) {
			matched.push( n );
		}
	}

	return matched;
};


var rneedsContext = jQuery.expr.match.needsContext;



function nodeName( elem, name ) {

	return elem.nodeName && elem.nodeName.toLowerCase() === name.toLowerCase();

}
var rsingleTag = ( /^<([a-z][^\/\0>:\x20\t\r\n\f]*)[\x20\t\r\n\f]*\/?>(?:<\/\1>|)$/i );



// Implement the identical functionality for filter and not
function winnow( elements, qualifier, not ) {
	if ( isFunction( qualifier ) ) {
		return jQuery.grep( elements, function( elem, i ) {
			return !!qualifier.call( elem, i, elem ) !== not;
		} );
	}

	// Single element
	if ( qualifier.nodeType ) {
		return jQuery.grep( elements, function( elem ) {
			return ( elem === qualifier ) !== not;
		} );
	}

	// Arraylike of elements (jQuery, arguments, Array)
	if ( typeof qualifier !== "string" ) {
		return jQuery.grep( elements, function( elem ) {
			return ( indexOf.call( qualifier, elem ) > -1 ) !== not;
		} );
	}

	// Filtered directly for both simple and complex selectors
	return jQuery.filter( qualifier, elements, not );
}

jQuery.filter = function( expr, elems, not ) {
	var elem = elems[ 0 ];

	if ( not ) {
		expr = ":not(" + expr + ")";
	}

	if ( elems.length === 1 && elem.nodeType === 1 ) {
		return jQuery.find.matchesSelector( elem, expr ) ? [ elem ] : [];
	}

	return jQuery.find.matches( expr, jQuery.grep( elems, function( elem ) {
		return elem.nodeType === 1;
	} ) );
};

jQuery.fn.extend( {
	find: function( selector ) {
		var i, ret,
			len = this.length,
			self = this;

		if ( typeof selector !== "string" ) {
			return this.pushStack( jQuery( selector ).filter( function() {
				for ( i = 0; i < len; i++ ) {
					if ( jQuery.contains( self[ i ], this ) ) {
						return true;
					}
				}
			} ) );
		}

		ret = this.pushStack( [] );

		for ( i = 0; i < len; i++ ) {
			jQuery.find( selector, self[ i ], ret );
		}

		return len > 1 ? jQuery.uniqueSort( ret ) : ret;
	},
	filter: function( selector ) {
		return this.pushStack( winnow( this, selector || [], false ) );
	},
	not: function( selector ) {
		return this.pushStack( winnow( this, selector || [], true ) );
	},
	is: function( selector ) {
		return !!winnow(
			this,

			// If this is a positional/relative selector, check membership in the returned set
			// so $("p:first").is("p:last") won't return true for a doc with two "p".
			typeof selector === "string" && rneedsContext.test( selector ) ?
				jQuery( selector ) :
				selector || [],
			false
		).length;
	}
} );


// Initialize a jQuery object


// A central reference to the root jQuery(document)
var rootjQuery,

	// A simple way to check for HTML strings
	// Prioritize #id over <tag> to avoid XSS via location.hash (#9521)
	// Strict HTML recognition (#11290: must start with <)
	// Shortcut simple #id case for speed
	rquickExpr = /^(?:\s*(<[\w\W]+>)[^>]*|#([\w-]+))$/,

	init = jQuery.fn.init = function( selector, context, root ) {
		var match, elem;

		// HANDLE: $(""), $(null), $(undefined), $(false)
		if ( !selector ) {
			return this;
		}

		// Method init() accepts an alternate rootjQuery
		// so migrate can support jQuery.sub (gh-2101)
		root = root || rootjQuery;

		// Handle HTML strings
		if ( typeof selector === "string" ) {
			if ( selector[ 0 ] === "<" &&
				selector[ selector.length - 1 ] === ">" &&
				selector.length >= 3 ) {

				// Assume that strings that start and end with <> are HTML and skip the regex check
				match = [ null, selector, null ];

			} else {
				match = rquickExpr.exec( selector );
			}

			// Match html or make sure no context is specified for #id
			if ( match && ( match[ 1 ] || !context ) ) {

				// HANDLE: $(html) -> $(array)
				if ( match[ 1 ] ) {
					context = context instanceof jQuery ? context[ 0 ] : context;

					// Option to run scripts is true for back-compat
					// Intentionally let the error be thrown if parseHTML is not present
					jQuery.merge( this, jQuery.parseHTML(
						match[ 1 ],
						context && context.nodeType ? context.ownerDocument || context : document,
						true
					) );

					// HANDLE: $(html, props)
					if ( rsingleTag.test( match[ 1 ] ) && jQuery.isPlainObject( context ) ) {
						for ( match in context ) {

							// Properties of context are called as methods if possible
							if ( isFunction( this[ match ] ) ) {
								this[ match ]( context[ match ] );

							// ...and otherwise set as attributes
							} else {
								this.attr( match, context[ match ] );
							}
						}
					}

					return this;

				// HANDLE: $(#id)
				} else {
					elem = document.getElementById( match[ 2 ] );

					if ( elem ) {

						// Inject the element directly into the jQuery object
						this[ 0 ] = elem;
						this.length = 1;
					}
					return this;
				}

			// HANDLE: $(expr, $(...))
			} else if ( !context || context.jquery ) {
				return ( context || root ).find( selector );

			// HANDLE: $(expr, context)
			// (which is just equivalent to: $(context).find(expr)
			} else {
				return this.constructor( context ).find( selector );
			}

		// HANDLE: $(DOMElement)
		} else if ( selector.nodeType ) {
			this[ 0 ] = selector;
			this.length = 1;
			return this;

		// HANDLE: $(function)
		// Shortcut for document ready
		} else if ( isFunction( selector ) ) {
			return root.ready !== undefined ?
				root.ready( selector ) :

				// Execute immediately if ready is not present
				selector( jQuery );
		}

		return jQuery.makeArray( selector, this );
	};

// Give the init function the jQuery prototype for later instantiation
init.prototype = jQuery.fn;

// Initialize central reference
rootjQuery = jQuery( document );


var rparentsprev = /^(?:parents|prev(?:Until|All))/,

	// Methods guaranteed to produce a unique set when starting from a unique set
	guaranteedUnique = {
		children: true,
		contents: true,
		next: true,
		prev: true
	};

jQuery.fn.extend( {
	has: function( target ) {
		var targets = jQuery( target, this ),
			l = targets.length;

		return this.filter( function() {
			var i = 0;
			for ( ; i < l; i++ ) {
				if ( jQuery.contains( this, targets[ i ] ) ) {
					return true;
				}
			}
		} );
	},

	closest: function( selectors, context ) {
		var cur,
			i = 0,
			l = this.length,
			matched = [],
			targets = typeof selectors !== "string" && jQuery( selectors );

		// Positional selectors never match, since there's no _selection_ context
		if ( !rneedsContext.test( selectors ) ) {
			for ( ; i < l; i++ ) {
				for ( cur = this[ i ]; cur && cur !== context; cur = cur.parentNode ) {

					// Always skip document fragments
					if ( cur.nodeType < 11 && ( targets ?
						targets.index( cur ) > -1 :

						// Don't pass non-elements to Sizzle
						cur.nodeType === 1 &&
							jQuery.find.matchesSelector( cur, selectors ) ) ) {

						matched.push( cur );
						break;
					}
				}
			}
		}

		return this.pushStack( matched.length > 1 ? jQuery.uniqueSort( matched ) : matched );
	},

	// Determine the position of an element within the set
	index: function( elem ) {

		// No argument, return index in parent
		if ( !elem ) {
			return ( this[ 0 ] && this[ 0 ].parentNode ) ? this.first().prevAll().length : -1;
		}

		// Index in selector
		if ( typeof elem === "string" ) {
			return indexOf.call( jQuery( elem ), this[ 0 ] );
		}

		// Locate the position of the desired element
		return indexOf.call( this,

			// If it receives a jQuery object, the first element is used
			elem.jquery ? elem[ 0 ] : elem
		);
	},

	add: function( selector, context ) {
		return this.pushStack(
			jQuery.uniqueSort(
				jQuery.merge( this.get(), jQuery( selector, context ) )
			)
		);
	},

	addBack: function( selector ) {
		return this.add( selector == null ?
			this.prevObject : this.prevObject.filter( selector )
		);
	}
} );

function sibling( cur, dir ) {
	while ( ( cur = cur[ dir ] ) && cur.nodeType !== 1 ) {}
	return cur;
}

jQuery.each( {
	parent: function( elem ) {
		var parent = elem.parentNode;
		return parent && parent.nodeType !== 11 ? parent : null;
	},
	parents: function( elem ) {
		return dir( elem, "parentNode" );
	},
	parentsUntil: function( elem, _i, until ) {
		return dir( elem, "parentNode", until );
	},
	next: function( elem ) {
		return sibling( elem, "nextSibling" );
	},
	prev: function( elem ) {
		return sibling( elem, "previousSibling" );
	},
	nextAll: function( elem ) {
		return dir( elem, "nextSibling" );
	},
	prevAll: function( elem ) {
		return dir( elem, "previousSibling" );
	},
	nextUntil: function( elem, _i, until ) {
		return dir( elem, "nextSibling", until );
	},
	prevUntil: function( elem, _i, until ) {
		return dir( elem, "previousSibling", until );
	},
	siblings: function( elem ) {
		return siblings( ( elem.parentNode || {} ).firstChild, elem );
	},
	children: function( elem ) {
		return siblings( elem.firstChild );
	},
	contents: function( elem ) {
		if ( elem.contentDocument != null &&

			// Support: IE 11+
			// <object> elements with no `data` attribute has an object
			// `contentDocument` with a `null` prototype.
			getProto( elem.contentDocument ) ) {

			return elem.contentDocument;
		}

		// Support: IE 9 - 11 only, iOS 7 only, Android Browser <=4.3 only
		// Treat the template element as a regular one in browsers that
		// don't support it.
		if ( nodeName( elem, "template" ) ) {
			elem = elem.content || elem;
		}

		return jQuery.merge( [], elem.childNodes );
	}
}, function( name, fn ) {
	jQuery.fn[ name ] = function( until, selector ) {
		var matched = jQuery.map( this, fn, until );

		if ( name.slice( -5 ) !== "Until" ) {
			selector = until;
		}

		if ( selector && typeof selector === "string" ) {
			matched = jQuery.filter( selector, matched );
		}

		if ( this.length > 1 ) {

			// Remove duplicates
			if ( !guaranteedUnique[ name ] ) {
				jQuery.uniqueSort( matched );
			}

			// Reverse order for parents* and prev-derivatives
			if ( rparentsprev.test( name ) ) {
				matched.reverse();
			}
		}

		return this.pushStack( matched );
	};
} );
var rnothtmlwhite = ( /[^\x20\t\r\n\f]+/g );



// Convert String-formatted options into Object-formatted ones
function createOptions( options ) {
	var object = {};
	jQuery.each( options.match( rnothtmlwhite ) || [], function( _, flag ) {
		object[ flag ] = true;
	} );
	return object;
}

/*
 * Create a callback list using the following parameters:
 *
 *	options: an optional list of space-separated options that will change how
 *			the callback list behaves or a more traditional option object
 *
 * By default a callback list will act like an event callback list and can be
 * "fired" multiple times.
 *
 * Possible options:
 *
 *	once:			will ensure the callback list can only be fired once (like a Deferred)
 *
 *	memory:			will keep track of previous values and will call any callback added
 *					after the list has been fired right away with the latest "memorized"
 *					values (like a Deferred)
 *
 *	unique:			will ensure a callback can only be added once (no duplicate in the list)
 *
 *	stopOnFalse:	interrupt callings when a callback returns false
 *
 */
jQuery.Callbacks = function( options ) {

	// Convert options from String-formatted to Object-formatted if needed
	// (we check in cache first)
	options = typeof options === "string" ?
		createOptions( options ) :
		jQuery.extend( {}, options );

	var // Flag to know if list is currently firing
		firing,

		// Last fire value for non-forgettable lists
		memory,

		// Flag to know if list was already fired
		fired,

		// Flag to prevent firing
		locked,

		// Actual callback list
		list = [],

		// Queue of execution data for repeatable lists
		queue = [],

		// Index of currently firing callback (modified by add/remove as needed)
		firingIndex = -1,

		// Fire callbacks
		fire = function() {

			// Enforce single-firing
			locked = locked || options.once;

			// Execute callbacks for all pending executions,
			// respecting firingIndex overrides and runtime changes
			fired = firing = true;
			for ( ; queue.length; firingIndex = -1 ) {
				memory = queue.shift();
				while ( ++firingIndex < list.length ) {

					// Run callback and check for early termination
					if ( list[ firingIndex ].apply( memory[ 0 ], memory[ 1 ] ) === false &&
						options.stopOnFalse ) {

						// Jump to end and forget the data so .add doesn't re-fire
						firingIndex = list.length;
						memory = false;
					}
				}
			}

			// Forget the data if we're done with it
			if ( !options.memory ) {
				memory = false;
			}

			firing = false;

			// Clean up if we're done firing for good
			if ( locked ) {

				// Keep an empty list if we have data for future add calls
				if ( memory ) {
					list = [];

				// Otherwise, this object is spent
				} else {
					list = "";
				}
			}
		},

		// Actual Callbacks object
		self = {

			// Add a callback or a collection of callbacks to the list
			add: function() {
				if ( list ) {

					// If we have memory from a past run, we should fire after adding
					if ( memory && !firing ) {
						firingIndex = list.length - 1;
						queue.push( memory );
					}

					( function add( args ) {
						jQuery.each( args, function( _, arg ) {
							if ( isFunction( arg ) ) {
								if ( !options.unique || !self.has( arg ) ) {
									list.push( arg );
								}
							} else if ( arg && arg.length && toType( arg ) !== "string" ) {

								// Inspect recursively
								add( arg );
							}
						} );
					} )( arguments );

					if ( memory && !firing ) {
						fire();
					}
				}
				return this;
			},

			// Remove a callback from the list
			remove: function() {
				jQuery.each( arguments, function( _, arg ) {
					var index;
					while ( ( index = jQuery.inArray( arg, list, index ) ) > -1 ) {
						list.splice( index, 1 );

						// Handle firing indexes
						if ( index <= firingIndex ) {
							firingIndex--;
						}
					}
				} );
				return this;
			},

			// Check if a given callback is in the list.
			// If no argument is given, return whether or not list has callbacks attached.
			has: function( fn ) {
				return fn ?
					jQuery.inArray( fn, list ) > -1 :
					list.length > 0;
			},

			// Remove all callbacks from the list
			empty: function() {
				if ( list ) {
					list = [];
				}
				return this;
			},

			// Disable .fire and .add
			// Abort any current/pending executions
			// Clear all callbacks and values
			disable: function() {
				locked = queue = [];
				list = memory = "";
				return this;
			},
			disabled: function() {
				return !list;
			},

			// Disable .fire
			// Also disable .add unless we have memory (since it would have no effect)
			// Abort any pending executions
			lock: function() {
				locked = queue = [];
				if ( !memory && !firing ) {
					list = memory = "";
				}
				return this;
			},
			locked: function() {
				return !!locked;
			},

			// Call all callbacks with the given context and arguments
			fireWith: function( context, args ) {
				if ( !locked ) {
					args = args || [];
					args = [ context, args.slice ? args.slice() : args ];
					queue.push( args );
					if ( !firing ) {
						fire();
					}
				}
				return this;
			},

			// Call all the callbacks with the given arguments
			fire: function() {
				self.fireWith( this, arguments );
				return this;
			},

			// To know if the callbacks have already been called at least once
			fired: function() {
				return !!fired;
			}
		};

	return self;
};


function Identity( v ) {
	return v;
}
function Thrower( ex ) {
	throw ex;
}

function adoptValue( value, resolve, reject, noValue ) {
	var method;

	try {

		// Check for promise aspect first to privilege synchronous behavior
		if ( value && isFunction( ( method = value.promise ) ) ) {
			method.call( value ).done( resolve ).fail( reject );

		// Other thenables
		} else if ( value && isFunction( ( method = value.then ) ) ) {
			method.call( value, resolve, reject );

		// Other non-thenables
		} else {

			// Control `resolve` arguments by letting Array#slice cast boolean `noValue` to integer:
			// * false: [ value ].slice( 0 ) => resolve( value )
			// * true: [ value ].slice( 1 ) => resolve()
			resolve.apply( undefined, [ value ].slice( noValue ) );
		}

	// For Promises/A+, convert exceptions into rejections
	// Since jQuery.when doesn't unwrap thenables, we can skip the extra checks appearing in
	// Deferred#then to conditionally suppress rejection.
	} catch ( value ) {

		// Support: Android 4.0 only
		// Strict mode functions invoked without .call/.apply get global-object context
		reject.apply( undefined, [ value ] );
	}
}

jQuery.extend( {

	Deferred: function( func ) {
		var tuples = [

				// action, add listener, callbacks,
				// ... .then handlers, argument index, [final state]
				[ "notify", "progress", jQuery.Callbacks( "memory" ),
					jQuery.Callbacks( "memory" ), 2 ],
				[ "resolve", "done", jQuery.Callbacks( "once memory" ),
					jQuery.Callbacks( "once memory" ), 0, "resolved" ],
				[ "reject", "fail", jQuery.Callbacks( "once memory" ),
					jQuery.Callbacks( "once memory" ), 1, "rejected" ]
			],
			state = "pending",
			promise = {
				state: function() {
					return state;
				},
				always: function() {
					deferred.done( arguments ).fail( arguments );
					return this;
				},
				"catch": function( fn ) {
					return promise.then( null, fn );
				},

				// Keep pipe for back-compat
				pipe: function( /* fnDone, fnFail, fnProgress */ ) {
					var fns = arguments;

					return jQuery.Deferred( function( newDefer ) {
						jQuery.each( tuples, function( _i, tuple ) {

							// Map tuples (progress, done, fail) to arguments (done, fail, progress)
							var fn = isFunction( fns[ tuple[ 4 ] ] ) && fns[ tuple[ 4 ] ];

							// deferred.progress(function() { bind to newDefer or newDefer.notify })
							// deferred.done(function() { bind to newDefer or newDefer.resolve })
							// deferred.fail(function() { bind to newDefer or newDefer.reject })
							deferred[ tuple[ 1 ] ]( function() {
								var returned = fn && fn.apply( this, arguments );
								if ( returned && isFunction( returned.promise ) ) {
									returned.promise()
										.progress( newDefer.notify )
										.done( newDefer.resolve )
										.fail( newDefer.reject );
								} else {
									newDefer[ tuple[ 0 ] + "With" ](
										this,
										fn ? [ returned ] : arguments
									);
								}
							} );
						} );
						fns = null;
					} ).promise();
				},
				then: function( onFulfilled, onRejected, onProgress ) {
					var maxDepth = 0;
					function resolve( depth, deferred, handler, special ) {
						return function() {
							var that = this,
								args = arguments,
								mightThrow = function() {
									var returned, then;

									// Support: Promises/A+ section 2.3.3.3.3
									// https://promisesaplus.com/#point-59
									// Ignore double-resolution attempts
									if ( depth < maxDepth ) {
										return;
									}

									returned = handler.apply( that, args );

									// Support: Promises/A+ section 2.3.1
									// https://promisesaplus.com/#point-48
									if ( returned === deferred.promise() ) {
										throw new TypeError( "Thenable self-resolution" );
									}

									// Support: Promises/A+ sections 2.3.3.1, 3.5
									// https://promisesaplus.com/#point-54
									// https://promisesaplus.com/#point-75
									// Retrieve `then` only once
									then = returned &&

										// Support: Promises/A+ section 2.3.4
										// https://promisesaplus.com/#point-64
										// Only check objects and functions for thenability
										( typeof returned === "object" ||
											typeof returned === "function" ) &&
										returned.then;

									// Handle a returned thenable
									if ( isFunction( then ) ) {

										// Special processors (notify) just wait for resolution
										if ( special ) {
											then.call(
												returned,
												resolve( maxDepth, deferred, Identity, special ),
												resolve( maxDepth, deferred, Thrower, special )
											);

										// Normal processors (resolve) also hook into progress
										} else {

											// ...and disregard older resolution values
											maxDepth++;

											then.call(
												returned,
												resolve( maxDepth, deferred, Identity, special ),
												resolve( maxDepth, deferred, Thrower, special ),
												resolve( maxDepth, deferred, Identity,
													deferred.notifyWith )
											);
										}

									// Handle all other returned values
									} else {

										// Only substitute handlers pass on context
										// and multiple values (non-spec behavior)
										if ( handler !== Identity ) {
											that = undefined;
											args = [ returned ];
										}

										// Process the value(s)
										// Default process is resolve
										( special || deferred.resolveWith )( that, args );
									}
								},

								// Only normal processors (resolve) catch and reject exceptions
								process = special ?
									mightThrow :
									function() {
										try {
											mightThrow();
										} catch ( e ) {

											if ( jQuery.Deferred.exceptionHook ) {
												jQuery.Deferred.exceptionHook( e,
													process.stackTrace );
											}

											// Support: Promises/A+ section 2.3.3.3.4.1
											// https://promisesaplus.com/#point-61
											// Ignore post-resolution exceptions
											if ( depth + 1 >= maxDepth ) {

												// Only substitute handlers pass on context
												// and multiple values (non-spec behavior)
												if ( handler !== Thrower ) {
													that = undefined;
													args = [ e ];
												}

												deferred.rejectWith( that, args );
											}
										}
									};

							// Support: Promises/A+ section 2.3.3.3.1
							// https://promisesaplus.com/#point-57
							// Re-resolve promises immediately to dodge false rejection from
							// subsequent errors
							if ( depth ) {
								process();
							} else {

								// Call an optional hook to record the stack, in case of exception
								// since it's otherwise lost when execution goes async
								if ( jQuery.Deferred.getStackHook ) {
									process.stackTrace = jQuery.Deferred.getStackHook();
								}
								window.setTimeout( process );
							}
						};
					}

					return jQuery.Deferred( function( newDefer ) {

						// progress_handlers.add( ... )
						tuples[ 0 ][ 3 ].add(
							resolve(
								0,
								newDefer,
								isFunction( onProgress ) ?
									onProgress :
									Identity,
								newDefer.notifyWith
							)
						);

						// fulfilled_handlers.add( ... )
						tuples[ 1 ][ 3 ].add(
							resolve(
								0,
								newDefer,
								isFunction( onFulfilled ) ?
									onFulfilled :
									Identity
							)
						);

						// rejected_handlers.add( ... )
						tuples[ 2 ][ 3 ].add(
							resolve(
								0,
								newDefer,
								isFunction( onRejected ) ?
									onRejected :
									Thrower
							)
						);
					} ).promise();
				},

				// Get a promise for this deferred
				// If obj is provided, the promise aspect is added to the object
				promise: function( obj ) {
					return obj != null ? jQuery.extend( obj, promise ) : promise;
				}
			},
			deferred = {};

		// Add list-specific methods
		jQuery.each( tuples, function( i, tuple ) {
			var list = tuple[ 2 ],
				stateString = tuple[ 5 ];

			// promise.progress = list.add
			// promise.done = list.add
			// promise.fail = list.add
			promise[ tuple[ 1 ] ] = list.add;

			// Handle state
			if ( stateString ) {
				list.add(
					function() {

						// state = "resolved" (i.e., fulfilled)
						// state = "rejected"
						state = stateString;
					},

					// rejected_callbacks.disable
					// fulfilled_callbacks.disable
					tuples[ 3 - i ][ 2 ].disable,

					// rejected_handlers.disable
					// fulfilled_handlers.disable
					tuples[ 3 - i ][ 3 ].disable,

					// progress_callbacks.lock
					tuples[ 0 ][ 2 ].lock,

					// progress_handlers.lock
					tuples[ 0 ][ 3 ].lock
				);
			}

			// progress_handlers.fire
			// fulfilled_handlers.fire
			// rejected_handlers.fire
			list.add( tuple[ 3 ].fire );

			// deferred.notify = function() { deferred.notifyWith(...) }
			// deferred.resolve = function() { deferred.resolveWith(...) }
			// deferred.reject = function() { deferred.rejectWith(...) }
			deferred[ tuple[ 0 ] ] = function() {
				deferred[ tuple[ 0 ] + "With" ]( this === deferred ? undefined : this, arguments );
				return this;
			};

			// deferred.notifyWith = list.fireWith
			// deferred.resolveWith = list.fireWith
			// deferred.rejectWith = list.fireWith
			deferred[ tuple[ 0 ] + "With" ] = list.fireWith;
		} );

		// Make the deferred a promise
		promise.promise( deferred );

		// Call given func if any
		if ( func ) {
			func.call( deferred, deferred );
		}

		// All done!
		return deferred;
	},

	// Deferred helper
	when: function( singleValue ) {
		var

			// count of uncompleted subordinates
			remaining = arguments.length,

			// count of unprocessed arguments
			i = remaining,

			// subordinate fulfillment data
			resolveContexts = Array( i ),
			resolveValues = slice.call( arguments ),

			// the primary Deferred
			primary = jQuery.Deferred(),

			// subordinate callback factory
			updateFunc = function( i ) {
				return function( value ) {
					resolveContexts[ i ] = this;
					resolveValues[ i ] = arguments.length > 1 ? slice.call( arguments ) : value;
					if ( !( --remaining ) ) {
						primary.resolveWith( resolveContexts, resolveValues );
					}
				};
			};

		// Single- and empty arguments are adopted like Promise.resolve
		if ( remaining <= 1 ) {
			adoptValue( singleValue, primary.done( updateFunc( i ) ).resolve, primary.reject,
				!remaining );

			// Use .then() to unwrap secondary thenables (cf. gh-3000)
			if ( primary.state() === "pending" ||
				isFunction( resolveValues[ i ] && resolveValues[ i ].then ) ) {

				return primary.then();
			}
		}

		// Multiple arguments are aggregated like Promise.all array elements
		while ( i-- ) {
			adoptValue( resolveValues[ i ], updateFunc( i ), primary.reject );
		}

		return primary.promise();
	}
} );


// These usually indicate a programmer mistake during development,
// warn about them ASAP rather than swallowing them by default.
var rerrorNames = /^(Eval|Internal|Range|Reference|Syntax|Type|URI)Error$/;

jQuery.Deferred.exceptionHook = function( error, stack ) {

	// Support: IE 8 - 9 only
	// Console exists when dev tools are open, which can happen at any time
	if ( window.console && window.console.warn && error && rerrorNames.test( error.name ) ) {
		window.console.warn( "jQuery.Deferred exception: " + error.message, error.stack, stack );
	}
};




jQuery.readyException = function( error ) {
	window.setTimeout( function() {
		throw error;
	} );
};




// The deferred used on DOM ready
var readyList = jQuery.Deferred();

jQuery.fn.ready = function( fn ) {

	readyList
		.then( fn )

		// Wrap jQuery.readyException in a function so that the lookup
		// happens at the time of error handling instead of callback
		// registration.
		.catch( function( error ) {
			jQuery.readyException( error );
		} );

	return this;
};

jQuery.extend( {

	// Is the DOM ready to be used? Set to true once it occurs.
	isReady: false,

	// A counter to track how many items to wait for before
	// the ready event fires. See #6781
	readyWait: 1,

	// Handle when the DOM is ready
	ready: function( wait ) {

		// Abort if there are pending holds or we're already ready
		if ( wait === true ? --jQuery.readyWait : jQuery.isReady ) {
			return;
		}

		// Remember that the DOM is ready
		jQuery.isReady = true;

		// If a normal DOM Ready event fired, decrement, and wait if need be
		if ( wait !== true && --jQuery.readyWait > 0 ) {
			return;
		}

		// If there are functions bound, to execute
		readyList.resolveWith( document, [ jQuery ] );
	}
} );

jQuery.ready.then = readyList.then;

// The ready event handler and self cleanup method
function completed() {
	document.removeEventListener( "DOMContentLoaded", completed );
	window.removeEventListener( "load", completed );
	jQuery.ready();
}

// Catch cases where $(document).ready() is called
// after the browser event has already occurred.
// Support: IE <=9 - 10 only
// Older IE sometimes signals "interactive" too soon
if ( document.readyState === "complete" ||
	( document.readyState !== "loading" && !document.documentElement.doScroll ) ) {

	// Handle it asynchronously to allow scripts the opportunity to delay ready
	window.setTimeout( jQuery.ready );

} else {

	// Use the handy event callback
	document.addEventListener( "DOMContentLoaded", completed );

	// A fallback to window.onload, that will always work
	window.addEventListener( "load", completed );
}




// Multifunctional method to get and set values of a collection
// The value/s can optionally be executed if it's a function
var access = function( elems, fn, key, value, chainable, emptyGet, raw ) {
	var i = 0,
		len = elems.length,
		bulk = key == null;

	// Sets many values
	if ( toType( key ) === "object" ) {
		chainable = true;
		for ( i in key ) {
			access( elems, fn, i, key[ i ], true, emptyGet, raw );
		}

	// Sets one value
	} else if ( value !== undefined ) {
		chainable = true;

		if ( !isFunction( value ) ) {
			raw = true;
		}

		if ( bulk ) {

			// Bulk operations run against the entire set
			if ( raw ) {
				fn.call( elems, value );
				fn = null;

			// ...except when executing function values
			} else {
				bulk = fn;
				fn = function( elem, _key, value ) {
					return bulk.call( jQuery( elem ), value );
				};
			}
		}

		if ( fn ) {
			for ( ; i < len; i++ ) {
				fn(
					elems[ i ], key, raw ?
						value :
						value.call( elems[ i ], i, fn( elems[ i ], key ) )
				);
			}
		}
	}

	if ( chainable ) {
		return elems;
	}

	// Gets
	if ( bulk ) {
		return fn.call( elems );
	}

	return len ? fn( elems[ 0 ], key ) : emptyGet;
};


// Matches dashed string for camelizing
var rmsPrefix = /^-ms-/,
	rdashAlpha = /-([a-z])/g;

// Used by camelCase as callback to replace()
function fcamelCase( _all, letter ) {
	return letter.toUpperCase();
}

// Convert dashed to camelCase; used by the css and data modules
// Support: IE <=9 - 11, Edge 12 - 15
// Microsoft forgot to hump their vendor prefix (#9572)
function camelCase( string ) {
	return string.replace( rmsPrefix, "ms-" ).replace( rdashAlpha, fcamelCase );
}
var acceptData = function( owner ) {

	// Accepts only:
	//  - Node
	//    - Node.ELEMENT_NODE
	//    - Node.DOCUMENT_NODE
	//  - Object
	//    - Any
	return owner.nodeType === 1 || owner.nodeType === 9 || !( +owner.nodeType );
};




function Data() {
	this.expando = jQuery.expando + Data.uid++;
}

Data.uid = 1;

Data.prototype = {

	cache: function( owner ) {

		// Check if the owner object already has a cache
		var value = owner[ this.expando ];

		// If not, create one
		if ( !value ) {
			value = {};

			// We can accept data for non-element nodes in modern browsers,
			// but we should not, see #8335.
			// Always return an empty object.
			if ( acceptData( owner ) ) {

				// If it is a node unlikely to be stringify-ed or looped over
				// use plain assignment
				if ( owner.nodeType ) {
					owner[ this.expando ] = value;

				// Otherwise secure it in a non-enumerable property
				// configurable must be true to allow the property to be
				// deleted when data is removed
				} else {
					Object.defineProperty( owner, this.expando, {
						value: value,
						configurable: true
					} );
				}
			}
		}

		return value;
	},
	set: function( owner, data, value ) {
		var prop,
			cache = this.cache( owner );

		// Handle: [ owner, key, value ] args
		// Always use camelCase key (gh-2257)
		if ( typeof data === "string" ) {
			cache[ camelCase( data ) ] = value;

		// Handle: [ owner, { properties } ] args
		} else {

			// Copy the properties one-by-one to the cache object
			for ( prop in data ) {
				cache[ camelCase( prop ) ] = data[ prop ];
			}
		}
		return cache;
	},
	get: function( owner, key ) {
		return key === undefined ?
			this.cache( owner ) :

			// Always use camelCase key (gh-2257)
			owner[ this.expando ] && owner[ this.expando ][ camelCase( key ) ];
	},
	access: function( owner, key, value ) {

		// In cases where either:
		//
		//   1. No key was specified
		//   2. A string key was specified, but no value provided
		//
		// Take the "read" path and allow the get method to determine
		// which value to return, respectively either:
		//
		//   1. The entire cache object
		//   2. The data stored at the key
		//
		if ( key === undefined ||
				( ( key && typeof key === "string" ) && value === undefined ) ) {

			return this.get( owner, key );
		}

		// When the key is not a string, or both a key and value
		// are specified, set or extend (existing objects) with either:
		//
		//   1. An object of properties
		//   2. A key and value
		//
		this.set( owner, key, value );

		// Since the "set" path can have two possible entry points
		// return the expected data based on which path was taken[*]
		return value !== undefined ? value : key;
	},
	remove: function( owner, key ) {
		var i,
			cache = owner[ this.expando ];

		if ( cache === undefined ) {
			return;
		}

		if ( key !== undefined ) {

			// Support array or space separated string of keys
			if ( Array.isArray( key ) ) {

				// If key is an array of keys...
				// We always set camelCase keys, so remove that.
				key = key.map( camelCase );
			} else {
				key = camelCase( key );

				// If a key with the spaces exists, use it.
				// Otherwise, create an array by matching non-whitespace
				key = key in cache ?
					[ key ] :
					( key.match( rnothtmlwhite ) || [] );
			}

			i = key.length;

			while ( i-- ) {
				delete cache[ key[ i ] ];
			}
		}

		// Remove the expando if there's no more data
		if ( key === undefined || jQuery.isEmptyObject( cache ) ) {

			// Support: Chrome <=35 - 45
			// Webkit & Blink performance suffers when deleting properties
			// from DOM nodes, so set to undefined instead
			// https://bugs.chromium.org/p/chromium/issues/detail?id=378607 (bug restricted)
			if ( owner.nodeType ) {
				owner[ this.expando ] = undefined;
			} else {
				delete owner[ this.expando ];
			}
		}
	},
	hasData: function( owner ) {
		var cache = owner[ this.expando ];
		return cache !== undefined && !jQuery.isEmptyObject( cache );
	}
};
var dataPriv = new Data();

var dataUser = new Data();



//	Implementation Summary
//
//	1. Enforce API surface and semantic compatibility with 1.9.x branch
//	2. Improve the module's maintainability by reducing the storage
//		paths to a single mechanism.
//	3. Use the same single mechanism to support "private" and "user" data.
//	4. _Never_ expose "private" data to user code (TODO: Drop _data, _removeData)
//	5. Avoid exposing implementation details on user objects (eg. expando properties)
//	6. Provide a clear path for implementation upgrade to WeakMap in 2014

var rbrace = /^(?:\{[\w\W]*\}|\[[\w\W]*\])$/,
	rmultiDash = /[A-Z]/g;

function getData( data ) {
	if ( data === "true" ) {
		return true;
	}

	if ( data === "false" ) {
		return false;
	}

	if ( data === "null" ) {
		return null;
	}

	// Only convert to a number if it doesn't change the string
	if ( data === +data + "" ) {
		return +data;
	}

	if ( rbrace.test( data ) ) {
		return JSON.parse( data );
	}

	return data;
}

function dataAttr( elem, key, data ) {
	var name;

	// If nothing was found internally, try to fetch any
	// data from the HTML5 data-* attribute
	if ( data === undefined && elem.nodeType === 1 ) {
		name = "data-" + key.replace( rmultiDash, "-$&" ).toLowerCase();
		data = elem.getAttribute( name );

		if ( typeof data === "string" ) {
			try {
				data = getData( data );
			} catch ( e ) {}

			// Make sure we set the data so it isn't changed later
			dataUser.set( elem, key, data );
		} else {
			data = undefined;
		}
	}
	return data;
}

jQuery.extend( {
	hasData: function( elem ) {
		return dataUser.hasData( elem ) || dataPriv.hasData( elem );
	},

	data: function( elem, name, data ) {
		return dataUser.access( elem, name, data );
	},

	removeData: function( elem, name ) {
		dataUser.remove( elem, name );
	},

	// TODO: Now that all calls to _data and _removeData have been replaced
	// with direct calls to dataPriv methods, these can be deprecated.
	_data: function( elem, name, data ) {
		return dataPriv.access( elem, name, data );
	},

	_removeData: function( elem, name ) {
		dataPriv.remove( elem, name );
	}
} );

jQuery.fn.extend( {
	data: function( key, value ) {
		var i, name, data,
			elem = this[ 0 ],
			attrs = elem && elem.attributes;

		// Gets all values
		if ( key === undefined ) {
			if ( this.length ) {
				data = dataUser.get( elem );

				if ( elem.nodeType === 1 && !dataPriv.get( elem, "hasDataAttrs" ) ) {
					i = attrs.length;
					while ( i-- ) {

						// Support: IE 11 only
						// The attrs elements can be null (#14894)
						if ( attrs[ i ] ) {
							name = attrs[ i ].name;
							if ( name.indexOf( "data-" ) === 0 ) {
								name = camelCase( name.slice( 5 ) );
								dataAttr( elem, name, data[ name ] );
							}
						}
					}
					dataPriv.set( elem, "hasDataAttrs", true );
				}
			}

			return data;
		}

		// Sets multiple values
		if ( typeof key === "object" ) {
			return this.each( function() {
				dataUser.set( this, key );
			} );
		}

		return access( this, function( value ) {
			var data;

			// The calling jQuery object (element matches) is not empty
			// (and therefore has an element appears at this[ 0 ]) and the
			// `value` parameter was not undefined. An empty jQuery object
			// will result in `undefined` for elem = this[ 0 ] which will
			// throw an exception if an attempt to read a data cache is made.
			if ( elem && value === undefined ) {

				// Attempt to get data from the cache
				// The key will always be camelCased in Data
				data = dataUser.get( elem, key );
				if ( data !== undefined ) {
					return data;
				}

				// Attempt to "discover" the data in
				// HTML5 custom data-* attrs
				data = dataAttr( elem, key );
				if ( data !== undefined ) {
					return data;
				}

				// We tried really hard, but the data doesn't exist.
				return;
			}

			// Set the data...
			this.each( function() {

				// We always store the camelCased key
				dataUser.set( this, key, value );
			} );
		}, null, value, arguments.length > 1, null, true );
	},

	removeData: function( key ) {
		return this.each( function() {
			dataUser.remove( this, key );
		} );
	}
} );


jQuery.extend( {
	queue: function( elem, type, data ) {
		var queue;

		if ( elem ) {
			type = ( type || "fx" ) + "queue";
			queue = dataPriv.get( elem, type );

			// Speed up dequeue by getting out quickly if this is just a lookup
			if ( data ) {
				if ( !queue || Array.isArray( data ) ) {
					queue = dataPriv.access( elem, type, jQuery.makeArray( data ) );
				} else {
					queue.push( data );
				}
			}
			return queue || [];
		}
	},

	dequeue: function( elem, type ) {
		type = type || "fx";

		var queue = jQuery.queue( elem, type ),
			startLength = queue.length,
			fn = queue.shift(),
			hooks = jQuery._queueHooks( elem, type ),
			next = function() {
				jQuery.dequeue( elem, type );
			};

		// If the fx queue is dequeued, always remove the progress sentinel
		if ( fn === "inprogress" ) {
			fn = queue.shift();
			startLength--;
		}

		if ( fn ) {

			// Add a progress sentinel to prevent the fx queue from being
			// automatically dequeued
			if ( type === "fx" ) {
				queue.unshift( "inprogress" );
			}

			// Clear up the last queue stop function
			delete hooks.stop;
			fn.call( elem, next, hooks );
		}

		if ( !startLength && hooks ) {
			hooks.empty.fire();
		}
	},

	// Not public - generate a queueHooks object, or return the current one
	_queueHooks: function( elem, type ) {
		var key = type + "queueHooks";
		return dataPriv.get( elem, key ) || dataPriv.access( elem, key, {
			empty: jQuery.Callbacks( "once memory" ).add( function() {
				dataPriv.remove( elem, [ type + "queue", key ] );
			} )
		} );
	}
} );

jQuery.fn.extend( {
	queue: function( type, data ) {
		var setter = 2;

		if ( typeof type !== "string" ) {
			data = type;
			type = "fx";
			setter--;
		}

		if ( arguments.length < setter ) {
			return jQuery.queue( this[ 0 ], type );
		}

		return data === undefined ?
			this :
			this.each( function() {
				var queue = jQuery.queue( this, type, data );

				// Ensure a hooks for this queue
				jQuery._queueHooks( this, type );

				if ( type === "fx" && queue[ 0 ] !== "inprogress" ) {
					jQuery.dequeue( this, type );
				}
			} );
	},
	dequeue: function( type ) {
		return this.each( function() {
			jQuery.dequeue( this, type );
		} );
	},
	clearQueue: function( type ) {
		return this.queue( type || "fx", [] );
	},

	// Get a promise resolved when queues of a certain type
	// are emptied (fx is the type by default)
	promise: function( type, obj ) {
		var tmp,
			count = 1,
			defer = jQuery.Deferred(),
			elements = this,
			i = this.length,
			resolve = function() {
				if ( !( --count ) ) {
					defer.resolveWith( elements, [ elements ] );
				}
			};

		if ( typeof type !== "string" ) {
			obj = type;
			type = undefined;
		}
		type = type || "fx";

		while ( i-- ) {
			tmp = dataPriv.get( elements[ i ], type + "queueHooks" );
			if ( tmp && tmp.empty ) {
				count++;
				tmp.empty.add( resolve );
			}
		}
		resolve();
		return defer.promise( obj );
	}
} );
var pnum = ( /[+-]?(?:\d*\.|)\d+(?:[eE][+-]?\d+|)/ ).source;

var rcssNum = new RegExp( "^(?:([+-])=|)(" + pnum + ")([a-z%]*)$", "i" );


var cssExpand = [ "Top", "Right", "Bottom", "Left" ];

var documentElement = document.documentElement;



	var isAttached = function( elem ) {
			return jQuery.contains( elem.ownerDocument, elem );
		},
		composed = { composed: true };

	// Support: IE 9 - 11+, Edge 12 - 18+, iOS 10.0 - 10.2 only
	// Check attachment across shadow DOM boundaries when possible (gh-3504)
	// Support: iOS 10.0-10.2 only
	// Early iOS 10 versions support `attachShadow` but not `getRootNode`,
	// leading to errors. We need to check for `getRootNode`.
	if ( documentElement.getRootNode ) {
		isAttached = function( elem ) {
			return jQuery.contains( elem.ownerDocument, elem ) ||
				elem.getRootNode( composed ) === elem.ownerDocument;
		};
	}
var isHiddenWithinTree = function( elem, el ) {

		// isHiddenWithinTree might be called from jQuery#filter function;
		// in that case, element will be second argument
		elem = el || elem;

		// Inline style trumps all
		return elem.style.display === "none" ||
			elem.style.display === "" &&

			// Otherwise, check computed style
			// Support: Firefox <=43 - 45
			// Disconnected elements can have computed display: none, so first confirm that elem is
			// in the document.
			isAttached( elem ) &&

			jQuery.css( elem, "display" ) === "none";
	};



function adjustCSS( elem, prop, valueParts, tween ) {
	var adjusted, scale,
		maxIterations = 20,
		currentValue = tween ?
			function() {
				return tween.cur();
			} :
			function() {
				return jQuery.css( elem, prop, "" );
			},
		initial = currentValue(),
		unit = valueParts && valueParts[ 3 ] || ( jQuery.cssNumber[ prop ] ? "" : "px" ),

		// Starting value computation is required for potential unit mismatches
		initialInUnit = elem.nodeType &&
			( jQuery.cssNumber[ prop ] || unit !== "px" && +initial ) &&
			rcssNum.exec( jQuery.css( elem, prop ) );

	if ( initialInUnit && initialInUnit[ 3 ] !== unit ) {

		// Support: Firefox <=54
		// Halve the iteration target value to prevent interference from CSS upper bounds (gh-2144)
		initial = initial / 2;

		// Trust units reported by jQuery.css
		unit = unit || initialInUnit[ 3 ];

		// Iteratively approximate from a nonzero starting point
		initialInUnit = +initial || 1;

		while ( maxIterations-- ) {

			// Evaluate and update our best guess (doubling guesses that zero out).
			// Finish if the scale equals or crosses 1 (making the old*new product non-positive).
			jQuery.style( elem, prop, initialInUnit + unit );
			if ( ( 1 - scale ) * ( 1 - ( scale = currentValue() / initial || 0.5 ) ) <= 0 ) {
				maxIterations = 0;
			}
			initialInUnit = initialInUnit / scale;

		}

		initialInUnit = initialInUnit * 2;
		jQuery.style( elem, prop, initialInUnit + unit );

		// Make sure we update the tween properties later on
		valueParts = valueParts || [];
	}

	if ( valueParts ) {
		initialInUnit = +initialInUnit || +initial || 0;

		// Apply relative offset (+=/-=) if specified
		adjusted = valueParts[ 1 ] ?
			initialInUnit + ( valueParts[ 1 ] + 1 ) * valueParts[ 2 ] :
			+valueParts[ 2 ];
		if ( tween ) {
			tween.unit = unit;
			tween.start = initialInUnit;
			tween.end = adjusted;
		}
	}
	return adjusted;
}


var defaultDisplayMap = {};

function getDefaultDisplay( elem ) {
	var temp,
		doc = elem.ownerDocument,
		nodeName = elem.nodeName,
		display = defaultDisplayMap[ nodeName ];

	if ( display ) {
		return display;
	}

	temp = doc.body.appendChild( doc.createElement( nodeName ) );
	display = jQuery.css( temp, "display" );

	temp.parentNode.removeChild( temp );

	if ( display === "none" ) {
		display = "block";
	}
	defaultDisplayMap[ nodeName ] = display;

	return display;
}

function showHide( elements, show ) {
	var display, elem,
		values = [],
		index = 0,
		length = elements.length;

	// Determine new display value for elements that need to change
	for ( ; index < length; index++ ) {
		elem = elements[ index ];
		if ( !elem.style ) {
			continue;
		}

		display = elem.style.display;
		if ( show ) {

			// Since we force visibility upon cascade-hidden elements, an immediate (and slow)
			// check is required in this first loop unless we have a nonempty display value (either
			// inline or about-to-be-restored)
			if ( display === "none" ) {
				values[ index ] = dataPriv.get( elem, "display" ) || null;
				if ( !values[ index ] ) {
					elem.style.display = "";
				}
			}
			if ( elem.style.display === "" && isHiddenWithinTree( elem ) ) {
				values[ index ] = getDefaultDisplay( elem );
			}
		} else {
			if ( display !== "none" ) {
				values[ index ] = "none";

				// Remember what we're overwriting
				dataPriv.set( elem, "display", display );
			}
		}
	}

	// Set the display of the elements in a second loop to avoid constant reflow
	for ( index = 0; index < length; index++ ) {
		if ( values[ index ] != null ) {
			elements[ index ].style.display = values[ index ];
		}
	}

	return elements;
}

jQuery.fn.extend( {
	show: function() {
		return showHide( this, true );
	},
	hide: function() {
		return showHide( this );
	},
	toggle: function( state ) {
		if ( typeof state === "boolean" ) {
			return state ? this.show() : this.hide();
		}

		return this.each( function() {
			if ( isHiddenWithinTree( this ) ) {
				jQuery( this ).show();
			} else {
				jQuery( this ).hide();
			}
		} );
	}
} );
var rcheckableType = ( /^(?:checkbox|radio)$/i );

var rtagName = ( /<([a-z][^\/\0>\x20\t\r\n\f]*)/i );

var rscriptType = ( /^$|^module$|\/(?:java|ecma)script/i );



( function() {
	var fragment = document.createDocumentFragment(),
		div = fragment.appendChild( document.createElement( "div" ) ),
		input = document.createElement( "input" );

	// Support: Android 4.0 - 4.3 only
	// Check state lost if the name is set (#11217)
	// Support: Windows Web Apps (WWA)
	// `name` and `type` must use .setAttribute for WWA (#14901)
	input.setAttribute( "type", "radio" );
	input.setAttribute( "checked", "checked" );
	input.setAttribute( "name", "t" );

	div.appendChild( input );

	// Support: Android <=4.1 only
	// Older WebKit doesn't clone checked state correctly in fragments
	support.checkClone = div.cloneNode( true ).cloneNode( true ).lastChild.checked;

	// Support: IE <=11 only
	// Make sure textarea (and checkbox) defaultValue is properly cloned
	div.innerHTML = "<textarea>x</textarea>";
	support.noCloneChecked = !!div.cloneNode( true ).lastChild.defaultValue;

	// Support: IE <=9 only
	// IE <=9 replaces <option> tags with their contents when inserted outside of
	// the select element.
	div.innerHTML = "<option></option>";
	support.option = !!div.lastChild;
} )();


// We have to close these tags to support XHTML (#13200)
var wrapMap = {

	// XHTML parsers do not magically insert elements in the
	// same way that tag soup parsers do. So we cannot shorten
	// this by omitting <tbody> or other required elements.
	thead: [ 1, "<table>", "</table>" ],
	col: [ 2, "<table><colgroup>", "</colgroup></table>" ],
	tr: [ 2, "<table><tbody>", "</tbody></table>" ],
	td: [ 3, "<table><tbody><tr>", "</tr></tbody></table>" ],

	_default: [ 0, "", "" ]
};

wrapMap.tbody = wrapMap.tfoot = wrapMap.colgroup = wrapMap.caption = wrapMap.thead;
wrapMap.th = wrapMap.td;

// Support: IE <=9 only
if ( !support.option ) {
	wrapMap.optgroup = wrapMap.option = [ 1, "<select multiple='multiple'>", "</select>" ];
}


function getAll( context, tag ) {

	// Support: IE <=9 - 11 only
	// Use typeof to avoid zero-argument method invocation on host objects (#15151)
	var ret;

	if ( typeof context.getElementsByTagName !== "undefined" ) {
		ret = context.getElementsByTagName( tag || "*" );

	} else if ( typeof context.querySelectorAll !== "undefined" ) {
		ret = context.querySelectorAll( tag || "*" );

	} else {
		ret = [];
	}

	if ( tag === undefined || tag && nodeName( context, tag ) ) {
		return jQuery.merge( [ context ], ret );
	}

	return ret;
}


// Mark scripts as having already been evaluated
function setGlobalEval( elems, refElements ) {
	var i = 0,
		l = elems.length;

	for ( ; i < l; i++ ) {
		dataPriv.set(
			elems[ i ],
			"globalEval",
			!refElements || dataPriv.get( refElements[ i ], "globalEval" )
		);
	}
}


var rhtml = /<|&#?\w+;/;

function buildFragment( elems, context, scripts, selection, ignored ) {
	var elem, tmp, tag, wrap, attached, j,
		fragment = context.createDocumentFragment(),
		nodes = [],
		i = 0,
		l = elems.length;

	for ( ; i < l; i++ ) {
		elem = elems[ i ];

		if ( elem || elem === 0 ) {

			// Add nodes directly
			if ( toType( elem ) === "object" ) {

				// Support: Android <=4.0 only, PhantomJS 1 only
				// push.apply(_, arraylike) throws on ancient WebKit
				jQuery.merge( nodes, elem.nodeType ? [ elem ] : elem );

			// Convert non-html into a text node
			} else if ( !rhtml.test( elem ) ) {
				nodes.push( context.createTextNode( elem ) );

			// Convert html into DOM nodes
			} else {
				tmp = tmp || fragment.appendChild( context.createElement( "div" ) );

				// Deserialize a standard representation
				tag = ( rtagName.exec( elem ) || [ "", "" ] )[ 1 ].toLowerCase();
				wrap = wrapMap[ tag ] || wrapMap._default;
				tmp.innerHTML = wrap[ 1 ] + jQuery.htmlPrefilter( elem ) + wrap[ 2 ];

				// Descend through wrappers to the right content
				j = wrap[ 0 ];
				while ( j-- ) {
					tmp = tmp.lastChild;
				}

				// Support: Android <=4.0 only, PhantomJS 1 only
				// push.apply(_, arraylike) throws on ancient WebKit
				jQuery.merge( nodes, tmp.childNodes );

				// Remember the top-level container
				tmp = fragment.firstChild;

				// Ensure the created nodes are orphaned (#12392)
				tmp.textContent = "";
			}
		}
	}

	// Remove wrapper from fragment
	fragment.textContent = "";

	i = 0;
	while ( ( elem = nodes[ i++ ] ) ) {

		// Skip elements already in the context collection (trac-4087)
		if ( selection && jQuery.inArray( elem, selection ) > -1 ) {
			if ( ignored ) {
				ignored.push( elem );
			}
			continue;
		}

		attached = isAttached( elem );

		// Append to fragment
		tmp = getAll( fragment.appendChild( elem ), "script" );

		// Preserve script evaluation history
		if ( attached ) {
			setGlobalEval( tmp );
		}

		// Capture executables
		if ( scripts ) {
			j = 0;
			while ( ( elem = tmp[ j++ ] ) ) {
				if ( rscriptType.test( elem.type || "" ) ) {
					scripts.push( elem );
				}
			}
		}
	}

	return fragment;
}


var rtypenamespace = /^([^.]*)(?:\.(.+)|)/;

function returnTrue() {
	return true;
}

function returnFalse() {
	return false;
}

// Support: IE <=9 - 11+
// focus() and blur() are asynchronous, except when they are no-op.
// So expect focus to be synchronous when the element is already active,
// and blur to be synchronous when the element is not already active.
// (focus and blur are always synchronous in other supported browsers,
// this just defines when we can count on it).
function expectSync( elem, type ) {
	return ( elem === safeActiveElement() ) === ( type === "focus" );
}

// Support: IE <=9 only
// Accessing document.activeElement can throw unexpectedly
// https://bugs.jquery.com/ticket/13393
function safeActiveElement() {
	try {
		return document.activeElement;
	} catch ( err ) { }
}

function on( elem, types, selector, data, fn, one ) {
	var origFn, type;

	// Types can be a map of types/handlers
	if ( typeof types === "object" ) {

		// ( types-Object, selector, data )
		if ( typeof selector !== "string" ) {

			// ( types-Object, data )
			data = data || selector;
			selector = undefined;
		}
		for ( type in types ) {
			on( elem, type, selector, data, types[ type ], one );
		}
		return elem;
	}

	if ( data == null && fn == null ) {

		// ( types, fn )
		fn = selector;
		data = selector = undefined;
	} else if ( fn == null ) {
		if ( typeof selector === "string" ) {

			// ( types, selector, fn )
			fn = data;
			data = undefined;
		} else {

			// ( types, data, fn )
			fn = data;
			data = selector;
			selector = undefined;
		}
	}
	if ( fn === false ) {
		fn = returnFalse;
	} else if ( !fn ) {
		return elem;
	}

	if ( one === 1 ) {
		origFn = fn;
		fn = function( event ) {

			// Can use an empty set, since event contains the info
			jQuery().off( event );
			return origFn.apply( this, arguments );
		};

		// Use same guid so caller can remove using origFn
		fn.guid = origFn.guid || ( origFn.guid = jQuery.guid++ );
	}
	return elem.each( function() {
		jQuery.event.add( this, types, fn, data, selector );
	} );
}

/*
 * Helper functions for managing events -- not part of the public interface.
 * Props to Dean Edwards' addEvent library for many of the ideas.
 */
jQuery.event = {

	global: {},

	add: function( elem, types, handler, data, selector ) {

		var handleObjIn, eventHandle, tmp,
			events, t, handleObj,
			special, handlers, type, namespaces, origType,
			elemData = dataPriv.get( elem );

		// Only attach events to objects that accept data
		if ( !acceptData( elem ) ) {
			return;
		}

		// Caller can pass in an object of custom data in lieu of the handler
		if ( handler.handler ) {
			handleObjIn = handler;
			handler = handleObjIn.handler;
			selector = handleObjIn.selector;
		}

		// Ensure that invalid selectors throw exceptions at attach time
		// Evaluate against documentElement in case elem is a non-element node (e.g., document)
		if ( selector ) {
			jQuery.find.matchesSelector( documentElement, selector );
		}

		// Make sure that the handler has a unique ID, used to find/remove it later
		if ( !handler.guid ) {
			handler.guid = jQuery.guid++;
		}

		// Init the element's event structure and main handler, if this is the first
		if ( !( events = elemData.events ) ) {
			events = elemData.events = Object.create( null );
		}
		if ( !( eventHandle = elemData.handle ) ) {
			eventHandle = elemData.handle = function( e ) {

				// Discard the second event of a jQuery.event.trigger() and
				// when an event is called after a page has unloaded
				return typeof jQuery !== "undefined" && jQuery.event.triggered !== e.type ?
					jQuery.event.dispatch.apply( elem, arguments ) : undefined;
			};
		}

		// Handle multiple events separated by a space
		types = ( types || "" ).match( rnothtmlwhite ) || [ "" ];
		t = types.length;
		while ( t-- ) {
			tmp = rtypenamespace.exec( types[ t ] ) || [];
			type = origType = tmp[ 1 ];
			namespaces = ( tmp[ 2 ] || "" ).split( "." ).sort();

			// There *must* be a type, no attaching namespace-only handlers
			if ( !type ) {
				continue;
			}

			// If event changes its type, use the special event handlers for the changed type
			special = jQuery.event.special[ type ] || {};

			// If selector defined, determine special event api type, otherwise given type
			type = ( selector ? special.delegateType : special.bindType ) || type;

			// Update special based on newly reset type
			special = jQuery.event.special[ type ] || {};

			// handleObj is passed to all event handlers
			handleObj = jQuery.extend( {
				type: type,
				origType: origType,
				data: data,
				handler: handler,
				guid: handler.guid,
				selector: selector,
				needsContext: selector && jQuery.expr.match.needsContext.test( selector ),
				namespace: namespaces.join( "." )
			}, handleObjIn );

			// Init the event handler queue if we're the first
			if ( !( handlers = events[ type ] ) ) {
				handlers = events[ type ] = [];
				handlers.delegateCount = 0;

				// Only use addEventListener if the special events handler returns false
				if ( !special.setup ||
					special.setup.call( elem, data, namespaces, eventHandle ) === false ) {

					if ( elem.addEventListener ) {
						elem.addEventListener( type, eventHandle );
					}
				}
			}

			if ( special.add ) {
				special.add.call( elem, handleObj );

				if ( !handleObj.handler.guid ) {
					handleObj.handler.guid = handler.guid;
				}
			}

			// Add to the element's handler list, delegates in front
			if ( selector ) {
				handlers.splice( handlers.delegateCount++, 0, handleObj );
			} else {
				handlers.push( handleObj );
			}

			// Keep track of which events have ever been used, for event optimization
			jQuery.event.global[ type ] = true;
		}

	},

	// Detach an event or set of events from an element
	remove: function( elem, types, handler, selector, mappedTypes ) {

		var j, origCount, tmp,
			events, t, handleObj,
			special, handlers, type, namespaces, origType,
			elemData = dataPriv.hasData( elem ) && dataPriv.get( elem );

		if ( !elemData || !( events = elemData.events ) ) {
			return;
		}

		// Once for each type.namespace in types; type may be omitted
		types = ( types || "" ).match( rnothtmlwhite ) || [ "" ];
		t = types.length;
		while ( t-- ) {
			tmp = rtypenamespace.exec( types[ t ] ) || [];
			type = origType = tmp[ 1 ];
			namespaces = ( tmp[ 2 ] || "" ).split( "." ).sort();

			// Unbind all events (on this namespace, if provided) for the element
			if ( !type ) {
				for ( type in events ) {
					jQuery.event.remove( elem, type + types[ t ], handler, selector, true );
				}
				continue;
			}

			special = jQuery.event.special[ type ] || {};
			type = ( selector ? special.delegateType : special.bindType ) || type;
			handlers = events[ type ] || [];
			tmp = tmp[ 2 ] &&
				new RegExp( "(^|\\.)" + namespaces.join( "\\.(?:.*\\.|)" ) + "(\\.|$)" );

			// Remove matching events
			origCount = j = handlers.length;
			while ( j-- ) {
				handleObj = handlers[ j ];

				if ( ( mappedTypes || origType === handleObj.origType ) &&
					( !handler || handler.guid === handleObj.guid ) &&
					( !tmp || tmp.test( handleObj.namespace ) ) &&
					( !selector || selector === handleObj.selector ||
						selector === "**" && handleObj.selector ) ) {
					handlers.splice( j, 1 );

					if ( handleObj.selector ) {
						handlers.delegateCount--;
					}
					if ( special.remove ) {
						special.remove.call( elem, handleObj );
					}
				}
			}

			// Remove generic event handler if we removed something and no more handlers exist
			// (avoids potential for endless recursion during removal of special event handlers)
			if ( origCount && !handlers.length ) {
				if ( !special.teardown ||
					special.teardown.call( elem, namespaces, elemData.handle ) === false ) {

					jQuery.removeEvent( elem, type, elemData.handle );
				}

				delete events[ type ];
			}
		}

		// Remove data and the expando if it's no longer used
		if ( jQuery.isEmptyObject( events ) ) {
			dataPriv.remove( elem, "handle events" );
		}
	},

	dispatch: function( nativeEvent ) {

		var i, j, ret, matched, handleObj, handlerQueue,
			args = new Array( arguments.length ),

			// Make a writable jQuery.Event from the native event object
			event = jQuery.event.fix( nativeEvent ),

			handlers = (
				dataPriv.get( this, "events" ) || Object.create( null )
			)[ event.type ] || [],
			special = jQuery.event.special[ event.type ] || {};

		// Use the fix-ed jQuery.Event rather than the (read-only) native event
		args[ 0 ] = event;

		for ( i = 1; i < arguments.length; i++ ) {
			args[ i ] = arguments[ i ];
		}

		event.delegateTarget = this;

		// Call the preDispatch hook for the mapped type, and let it bail if desired
		if ( special.preDispatch && special.preDispatch.call( this, event ) === false ) {
			return;
		}

		// Determine handlers
		handlerQueue = jQuery.event.handlers.call( this, event, handlers );

		// Run delegates first; they may want to stop propagation beneath us
		i = 0;
		while ( ( matched = handlerQueue[ i++ ] ) && !event.isPropagationStopped() ) {
			event.currentTarget = matched.elem;

			j = 0;
			while ( ( handleObj = matched.handlers[ j++ ] ) &&
				!event.isImmediatePropagationStopped() ) {

				// If the event is namespaced, then each handler is only invoked if it is
				// specially universal or its namespaces are a superset of the event's.
				if ( !event.rnamespace || handleObj.namespace === false ||
					event.rnamespace.test( handleObj.namespace ) ) {

					event.handleObj = handleObj;
					event.data = handleObj.data;

					ret = ( ( jQuery.event.special[ handleObj.origType ] || {} ).handle ||
						handleObj.handler ).apply( matched.elem, args );

					if ( ret !== undefined ) {
						if ( ( event.result = ret ) === false ) {
							event.preventDefault();
							event.stopPropagation();
						}
					}
				}
			}
		}

		// Call the postDispatch hook for the mapped type
		if ( special.postDispatch ) {
			special.postDispatch.call( this, event );
		}

		return event.result;
	},

	handlers: function( event, handlers ) {
		var i, handleObj, sel, matchedHandlers, matchedSelectors,
			handlerQueue = [],
			delegateCount = handlers.delegateCount,
			cur = event.target;

		// Find delegate handlers
		if ( delegateCount &&

			// Support: IE <=9
			// Black-hole SVG <use> instance trees (trac-13180)
			cur.nodeType &&

			// Support: Firefox <=42
			// Suppress spec-violating clicks indicating a non-primary pointer button (trac-3861)
			// https://www.w3.org/TR/DOM-Level-3-Events/#event-type-click
			// Support: IE 11 only
			// ...but not arrow key "clicks" of radio inputs, which can have `button` -1 (gh-2343)
			!( event.type === "click" && event.button >= 1 ) ) {

			for ( ; cur !== this; cur = cur.parentNode || this ) {

				// Don't check non-elements (#13208)
				// Don't process clicks on disabled elements (#6911, #8165, #11382, #11764)
				if ( cur.nodeType === 1 && !( event.type === "click" && cur.disabled === true ) ) {
					matchedHandlers = [];
					matchedSelectors = {};
					for ( i = 0; i < delegateCount; i++ ) {
						handleObj = handlers[ i ];

						// Don't conflict with Object.prototype properties (#13203)
						sel = handleObj.selector + " ";

						if ( matchedSelectors[ sel ] === undefined ) {
							matchedSelectors[ sel ] = handleObj.needsContext ?
								jQuery( sel, this ).index( cur ) > -1 :
								jQuery.find( sel, this, null, [ cur ] ).length;
						}
						if ( matchedSelectors[ sel ] ) {
							matchedHandlers.push( handleObj );
						}
					}
					if ( matchedHandlers.length ) {
						handlerQueue.push( { elem: cur, handlers: matchedHandlers } );
					}
				}
			}
		}

		// Add the remaining (directly-bound) handlers
		cur = this;
		if ( delegateCount < handlers.length ) {
			handlerQueue.push( { elem: cur, handlers: handlers.slice( delegateCount ) } );
		}

		return handlerQueue;
	},

	addProp: function( name, hook ) {
		Object.defineProperty( jQuery.Event.prototype, name, {
			enumerable: true,
			configurable: true,

			get: isFunction( hook ) ?
				function() {
					if ( this.originalEvent ) {
						return hook( this.originalEvent );
					}
				} :
				function() {
					if ( this.originalEvent ) {
						return this.originalEvent[ name ];
					}
				},

			set: function( value ) {
				Object.defineProperty( this, name, {
					enumerable: true,
					configurable: true,
					writable: true,
					value: value
				} );
			}
		} );
	},

	fix: function( originalEvent ) {
		return originalEvent[ jQuery.expando ] ?
			originalEvent :
			new jQuery.Event( originalEvent );
	},

	special: {
		load: {

			// Prevent triggered image.load events from bubbling to window.load
			noBubble: true
		},
		click: {

			// Utilize native event to ensure correct state for checkable inputs
			setup: function( data ) {

				// For mutual compressibility with _default, replace `this` access with a local var.
				// `|| data` is dead code meant only to preserve the variable through minification.
				var el = this || data;

				// Claim the first handler
				if ( rcheckableType.test( el.type ) &&
					el.click && nodeName( el, "input" ) ) {

					// dataPriv.set( el, "click", ... )
					leverageNative( el, "click", returnTrue );
				}

				// Return false to allow normal processing in the caller
				return false;
			},
			trigger: function( data ) {

				// For mutual compressibility with _default, replace `this` access with a local var.
				// `|| data` is dead code meant only to preserve the variable through minification.
				var el = this || data;

				// Force setup before triggering a click
				if ( rcheckableType.test( el.type ) &&
					el.click && nodeName( el, "input" ) ) {

					leverageNative( el, "click" );
				}

				// Return non-false to allow normal event-path propagation
				return true;
			},

			// For cross-browser consistency, suppress native .click() on links
			// Also prevent it if we're currently inside a leveraged native-event stack
			_default: function( event ) {
				var target = event.target;
				return rcheckableType.test( target.type ) &&
					target.click && nodeName( target, "input" ) &&
					dataPriv.get( target, "click" ) ||
					nodeName( target, "a" );
			}
		},

		beforeunload: {
			postDispatch: function( event ) {

				// Support: Firefox 20+
				// Firefox doesn't alert if the returnValue field is not set.
				if ( event.result !== undefined && event.originalEvent ) {
					event.originalEvent.returnValue = event.result;
				}
			}
		}
	}
};

// Ensure the presence of an event listener that handles manually-triggered
// synthetic events by interrupting progress until reinvoked in response to
// *native* events that it fires directly, ensuring that state changes have
// already occurred before other listeners are invoked.
function leverageNative( el, type, expectSync ) {

	// Missing expectSync indicates a trigger call, which must force setup through jQuery.event.add
	if ( !expectSync ) {
		if ( dataPriv.get( el, type ) === undefined ) {
			jQuery.event.add( el, type, returnTrue );
		}
		return;
	}

	// Register the controller as a special universal handler for all event namespaces
	dataPriv.set( el, type, false );
	jQuery.event.add( el, type, {
		namespace: false,
		handler: function( event ) {
			var notAsync, result,
				saved = dataPriv.get( this, type );

			if ( ( event.isTrigger & 1 ) && this[ type ] ) {

				// Interrupt processing of the outer synthetic .trigger()ed event
				// Saved data should be false in such cases, but might be a leftover capture object
				// from an async native handler (gh-4350)
				if ( !saved.length ) {

					// Store arguments for use when handling the inner native event
					// There will always be at least one argument (an event object), so this array
					// will not be confused with a leftover capture object.
					saved = slice.call( arguments );
					dataPriv.set( this, type, saved );

					// Trigger the native event and capture its result
					// Support: IE <=9 - 11+
					// focus() and blur() are asynchronous
					notAsync = expectSync( this, type );
					this[ type ]();
					result = dataPriv.get( this, type );
					if ( saved !== result || notAsync ) {
						dataPriv.set( this, type, false );
					} else {
						result = {};
					}
					if ( saved !== result ) {

						// Cancel the outer synthetic event
						event.stopImmediatePropagation();
						event.preventDefault();

						// Support: Chrome 86+
						// In Chrome, if an element having a focusout handler is blurred by
						// clicking outside of it, it invokes the handler synchronously. If
						// that handler calls `.remove()` on the element, the data is cleared,
						// leaving `result` undefined. We need to guard against this.
						return result && result.value;
					}

				// If this is an inner synthetic event for an event with a bubbling surrogate
				// (focus or blur), assume that the surrogate already propagated from triggering the
				// native event and prevent that from happening again here.
				// This technically gets the ordering wrong w.r.t. to `.trigger()` (in which the
				// bubbling surrogate propagates *after* the non-bubbling base), but that seems
				// less bad than duplication.
				} else if ( ( jQuery.event.special[ type ] || {} ).delegateType ) {
					event.stopPropagation();
				}

			// If this is a native event triggered above, everything is now in order
			// Fire an inner synthetic event with the original arguments
			} else if ( saved.length ) {

				// ...and capture the result
				dataPriv.set( this, type, {
					value: jQuery.event.trigger(

						// Support: IE <=9 - 11+
						// Extend with the prototype to reset the above stopImmediatePropagation()
						jQuery.extend( saved[ 0 ], jQuery.Event.prototype ),
						saved.slice( 1 ),
						this
					)
				} );

				// Abort handling of the native event
				event.stopImmediatePropagation();
			}
		}
	} );
}

jQuery.removeEvent = function( elem, type, handle ) {

	// This "if" is needed for plain objects
	if ( elem.removeEventListener ) {
		elem.removeEventListener( type, handle );
	}
};

jQuery.Event = function( src, props ) {

	// Allow instantiation without the 'new' keyword
	if ( !( this instanceof jQuery.Event ) ) {
		return new jQuery.Event( src, props );
	}

	// Event object
	if ( src && src.type ) {
		this.originalEvent = src;
		this.type = src.type;

		// Events bubbling up the document may have been marked as prevented
		// by a handler lower down the tree; reflect the correct value.
		this.isDefaultPrevented = src.defaultPrevented ||
				src.defaultPrevented === undefined &&

				// Support: Android <=2.3 only
				src.returnValue === false ?
			returnTrue :
			returnFalse;

		// Create target properties
		// Support: Safari <=6 - 7 only
		// Target should not be a text node (#504, #13143)
		this.target = ( src.target && src.target.nodeType === 3 ) ?
			src.target.parentNode :
			src.target;

		this.currentTarget = src.currentTarget;
		this.relatedTarget = src.relatedTarget;

	// Event type
	} else {
		this.type = src;
	}

	// Put explicitly provided properties onto the event object
	if ( props ) {
		jQuery.extend( this, props );
	}

	// Create a timestamp if incoming event doesn't have one
	this.timeStamp = src && src.timeStamp || Date.now();

	// Mark it as fixed
	this[ jQuery.expando ] = true;
};

// jQuery.Event is based on DOM3 Events as specified by the ECMAScript Language Binding
// https://www.w3.org/TR/2003/WD-DOM-Level-3-Events-20030331/ecma-script-binding.html
jQuery.Event.prototype = {
	constructor: jQuery.Event,
	isDefaultPrevented: returnFalse,
	isPropagationStopped: returnFalse,
	isImmediatePropagationStopped: returnFalse,
	isSimulated: false,

	preventDefault: function() {
		var e = this.originalEvent;

		this.isDefaultPrevented = returnTrue;

		if ( e && !this.isSimulated ) {
			e.preventDefault();
		}
	},
	stopPropagation: function() {
		var e = this.originalEvent;

		this.isPropagationStopped = returnTrue;

		if ( e && !this.isSimulated ) {
			e.stopPropagation();
		}
	},
	stopImmediatePropagation: function() {
		var e = this.originalEvent;

		this.isImmediatePropagationStopped = returnTrue;

		if ( e && !this.isSimulated ) {
			e.stopImmediatePropagation();
		}

		this.stopPropagation();
	}
};

// Includes all common event props including KeyEvent and MouseEvent specific props
jQuery.each( {
	altKey: true,
	bubbles: true,
	cancelable: true,
	changedTouches: true,
	ctrlKey: true,
	detail: true,
	eventPhase: true,
	metaKey: true,
	pageX: true,
	pageY: true,
	shiftKey: true,
	view: true,
	"char": true,
	code: true,
	charCode: true,
	key: true,
	keyCode: true,
	button: true,
	buttons: true,
	clientX: true,
	clientY: true,
	offsetX: true,
	offsetY: true,
	pointerId: true,
	pointerType: true,
	screenX: true,
	screenY: true,
	targetTouches: true,
	toElement: true,
	touches: true,
	which: true
}, jQuery.event.addProp );

jQuery.each( { focus: "focusin", blur: "focusout" }, function( type, delegateType ) {
	jQuery.event.special[ type ] = {

		// Utilize native event if possible so blur/focus sequence is correct
		setup: function() {

			// Claim the first handler
			// dataPriv.set( this, "focus", ... )
			// dataPriv.set( this, "blur", ... )
			leverageNative( this, type, expectSync );

			// Return false to allow normal processing in the caller
			return false;
		},
		trigger: function() {

			// Force setup before trigger
			leverageNative( this, type );

			// Return non-false to allow normal event-path propagation
			return true;
		},

		// Suppress native focus or blur as it's already being fired
		// in leverageNative.
		_default: function() {
			return true;
		},

		delegateType: delegateType
	};
} );

// Create mouseenter/leave events using mouseover/out and event-time checks
// so that event delegation works in jQuery.
// Do the same for pointerenter/pointerleave and pointerover/pointerout
//
// Support: Safari 7 only
// Safari sends mouseenter too often; see:
// https://bugs.chromium.org/p/chromium/issues/detail?id=470258
// for the description of the bug (it existed in older Chrome versions as well).
jQuery.each( {
	mouseenter: "mouseover",
	mouseleave: "mouseout",
	pointerenter: "pointerover",
	pointerleave: "pointerout"
}, function( orig, fix ) {
	jQuery.event.special[ orig ] = {
		delegateType: fix,
		bindType: fix,

		handle: function( event ) {
			var ret,
				target = this,
				related = event.relatedTarget,
				handleObj = event.handleObj;

			// For mouseenter/leave call the handler if related is outside the target.
			// NB: No relatedTarget if the mouse left/entered the browser window
			if ( !related || ( related !== target && !jQuery.contains( target, related ) ) ) {
				event.type = handleObj.origType;
				ret = handleObj.handler.apply( this, arguments );
				event.type = fix;
			}
			return ret;
		}
	};
} );

jQuery.fn.extend( {

	on: function( types, selector, data, fn ) {
		return on( this, types, selector, data, fn );
	},
	one: function( types, selector, data, fn ) {
		return on( this, types, selector, data, fn, 1 );
	},
	off: function( types, selector, fn ) {
		var handleObj, type;
		if ( types && types.preventDefault && types.handleObj ) {

			// ( event )  dispatched jQuery.Event
			handleObj = types.handleObj;
			jQuery( types.delegateTarget ).off(
				handleObj.namespace ?
					handleObj.origType + "." + handleObj.namespace :
					handleObj.origType,
				handleObj.selector,
				handleObj.handler
			);
			return this;
		}
		if ( typeof types === "object" ) {

			// ( types-object [, selector] )
			for ( type in types ) {
				this.off( type, selector, types[ type ] );
			}
			return this;
		}
		if ( selector === false || typeof selector === "function" ) {

			// ( types [, fn] )
			fn = selector;
			selector = undefined;
		}
		if ( fn === false ) {
			fn = returnFalse;
		}
		return this.each( function() {
			jQuery.event.remove( this, types, fn, selector );
		} );
	}
} );


var

	// Support: IE <=10 - 11, Edge 12 - 13 only
	// In IE/Edge using regex groups here causes severe slowdowns.
	// See https://connect.microsoft.com/IE/feedback/details/1736512/
	rnoInnerhtml = /<script|<style|<link/i,

	// checked="checked" or checked
	rchecked = /checked\s*(?:[^=]|=\s*.checked.)/i,
	rcleanScript = /^\s*<!(?:\[CDATA\[|--)|(?:\]\]|--)>\s*$/g;

// Prefer a tbody over its parent table for containing new rows
function manipulationTarget( elem, content ) {
	if ( nodeName( elem, "table" ) &&
		nodeName( content.nodeType !== 11 ? content : content.firstChild, "tr" ) ) {

		return jQuery( elem ).children( "tbody" )[ 0 ] || elem;
	}

	return elem;
}

// Replace/restore the type attribute of script elements for safe DOM manipulation
function disableScript( elem ) {
	elem.type = ( elem.getAttribute( "type" ) !== null ) + "/" + elem.type;
	return elem;
}
function restoreScript( elem ) {
	if ( ( elem.type || "" ).slice( 0, 5 ) === "true/" ) {
		elem.type = elem.type.slice( 5 );
	} else {
		elem.removeAttribute( "type" );
	}

	return elem;
}

function cloneCopyEvent( src, dest ) {
	var i, l, type, pdataOld, udataOld, udataCur, events;

	if ( dest.nodeType !== 1 ) {
		return;
	}

	// 1. Copy private data: events, handlers, etc.
	if ( dataPriv.hasData( src ) ) {
		pdataOld = dataPriv.get( src );
		events = pdataOld.events;

		if ( events ) {
			dataPriv.remove( dest, "handle events" );

			for ( type in events ) {
				for ( i = 0, l = events[ type ].length; i < l; i++ ) {
					jQuery.event.add( dest, type, events[ type ][ i ] );
				}
			}
		}
	}

	// 2. Copy user data
	if ( dataUser.hasData( src ) ) {
		udataOld = dataUser.access( src );
		udataCur = jQuery.extend( {}, udataOld );

		dataUser.set( dest, udataCur );
	}
}

// Fix IE bugs, see support tests
function fixInput( src, dest ) {
	var nodeName = dest.nodeName.toLowerCase();

	// Fails to persist the checked state of a cloned checkbox or radio button.
	if ( nodeName === "input" && rcheckableType.test( src.type ) ) {
		dest.checked = src.checked;

	// Fails to return the selected option to the default selected state when cloning options
	} else if ( nodeName === "input" || nodeName === "textarea" ) {
		dest.defaultValue = src.defaultValue;
	}
}

function domManip( collection, args, callback, ignored ) {

	// Flatten any nested arrays
	args = flat( args );

	var fragment, first, scripts, hasScripts, node, doc,
		i = 0,
		l = collection.length,
		iNoClone = l - 1,
		value = args[ 0 ],
		valueIsFunction = isFunction( value );

	// We can't cloneNode fragments that contain checked, in WebKit
	if ( valueIsFunction ||
			( l > 1 && typeof value === "string" &&
				!support.checkClone && rchecked.test( value ) ) ) {
		return collection.each( function( index ) {
			var self = collection.eq( index );
			if ( valueIsFunction ) {
				args[ 0 ] = value.call( this, index, self.html() );
			}
			domManip( self, args, callback, ignored );
		} );
	}

	if ( l ) {
		fragment = buildFragment( args, collection[ 0 ].ownerDocument, false, collection, ignored );
		first = fragment.firstChild;

		if ( fragment.childNodes.length === 1 ) {
			fragment = first;
		}

		// Require either new content or an interest in ignored elements to invoke the callback
		if ( first || ignored ) {
			scripts = jQuery.map( getAll( fragment, "script" ), disableScript );
			hasScripts = scripts.length;

			// Use the original fragment for the last item
			// instead of the first because it can end up
			// being emptied incorrectly in certain situations (#8070).
			for ( ; i < l; i++ ) {
				node = fragment;

				if ( i !== iNoClone ) {
					node = jQuery.clone( node, true, true );

					// Keep references to cloned scripts for later restoration
					if ( hasScripts ) {

						// Support: Android <=4.0 only, PhantomJS 1 only
						// push.apply(_, arraylike) throws on ancient WebKit
						jQuery.merge( scripts, getAll( node, "script" ) );
					}
				}

				callback.call( collection[ i ], node, i );
			}

			if ( hasScripts ) {
				doc = scripts[ scripts.length - 1 ].ownerDocument;

				// Reenable scripts
				jQuery.map( scripts, restoreScript );

				// Evaluate executable scripts on first document insertion
				for ( i = 0; i < hasScripts; i++ ) {
					node = scripts[ i ];
					if ( rscriptType.test( node.type || "" ) &&
						!dataPriv.access( node, "globalEval" ) &&
						jQuery.contains( doc, node ) ) {

						if ( node.src && ( node.type || "" ).toLowerCase()  !== "module" ) {

							// Optional AJAX dependency, but won't run scripts if not present
							if ( jQuery._evalUrl && !node.noModule ) {
								jQuery._evalUrl( node.src, {
									nonce: node.nonce || node.getAttribute( "nonce" )
								}, doc );
							}
						} else {
							DOMEval( node.textContent.replace( rcleanScript, "" ), node, doc );
						}
					}
				}
			}
		}
	}

	return collection;
}

function remove( elem, selector, keepData ) {
	var node,
		nodes = selector ? jQuery.filter( selector, elem ) : elem,
		i = 0;

	for ( ; ( node = nodes[ i ] ) != null; i++ ) {
		if ( !keepData && node.nodeType === 1 ) {
			jQuery.cleanData( getAll( node ) );
		}

		if ( node.parentNode ) {
			if ( keepData && isAttached( node ) ) {
				setGlobalEval( getAll( node, "script" ) );
			}
			node.parentNode.removeChild( node );
		}
	}

	return elem;
}

jQuery.extend( {
	htmlPrefilter: function( html ) {
		return html;
	},

	clone: function( elem, dataAndEvents, deepDataAndEvents ) {
		var i, l, srcElements, destElements,
			clone = elem.cloneNode( true ),
			inPage = isAttached( elem );

		// Fix IE cloning issues
		if ( !support.noCloneChecked && ( elem.nodeType === 1 || elem.nodeType === 11 ) &&
				!jQuery.isXMLDoc( elem ) ) {

			// We eschew Sizzle here for performance reasons: https://jsperf.com/getall-vs-sizzle/2
			destElements = getAll( clone );
			srcElements = getAll( elem );

			for ( i = 0, l = srcElements.length; i < l; i++ ) {
				fixInput( srcElements[ i ], destElements[ i ] );
			}
		}

		// Copy the events from the original to the clone
		if ( dataAndEvents ) {
			if ( deepDataAndEvents ) {
				srcElements = srcElements || getAll( elem );
				destElements = destElements || getAll( clone );

				for ( i = 0, l = srcElements.length; i < l; i++ ) {
					cloneCopyEvent( srcElements[ i ], destElements[ i ] );
				}
			} else {
				cloneCopyEvent( elem, clone );
			}
		}

		// Preserve script evaluation history
		destElements = getAll( clone, "script" );
		if ( destElements.length > 0 ) {
			setGlobalEval( destElements, !inPage && getAll( elem, "script" ) );
		}

		// Return the cloned set
		return clone;
	},

	cleanData: function( elems ) {
		var data, elem, type,
			special = jQuery.event.special,
			i = 0;

		for ( ; ( elem = elems[ i ] ) !== undefined; i++ ) {
			if ( acceptData( elem ) ) {
				if ( ( data = elem[ dataPriv.expando ] ) ) {
					if ( data.events ) {
						for ( type in data.events ) {
							if ( special[ type ] ) {
								jQuery.event.remove( elem, type );

							// This is a shortcut to avoid jQuery.event.remove's overhead
							} else {
								jQuery.removeEvent( elem, type, data.handle );
							}
						}
					}

					// Support: Chrome <=35 - 45+
					// Assign undefined instead of using delete, see Data#remove
					elem[ dataPriv.expando ] = undefined;
				}
				if ( elem[ dataUser.expando ] ) {

					// Support: Chrome <=35 - 45+
					// Assign undefined instead of using delete, see Data#remove
					elem[ dataUser.expando ] = undefined;
				}
			}
		}
	}
} );

jQuery.fn.extend( {
	detach: function( selector ) {
		return remove( this, selector, true );
	},

	remove: function( selector ) {
		return remove( this, selector );
	},

	text: function( value ) {
		return access( this, function( value ) {
			return value === undefined ?
				jQuery.text( this ) :
				this.empty().each( function() {
					if ( this.nodeType === 1 || this.nodeType === 11 || this.nodeType === 9 ) {
						this.textContent = value;
					}
				} );
		}, null, value, arguments.length );
	},

	append: function() {
		return domManip( this, arguments, function( elem ) {
			if ( this.nodeType === 1 || this.nodeType === 11 || this.nodeType === 9 ) {
				var target = manipulationTarget( this, elem );
				target.appendChild( elem );
			}
		} );
	},

	prepend: function() {
		return domManip( this, arguments, function( elem ) {
			if ( this.nodeType === 1 || this.nodeType === 11 || this.nodeType === 9 ) {
				var target = manipulationTarget( this, elem );
				target.insertBefore( elem, target.firstChild );
			}
		} );
	},

	before: function() {
		return domManip( this, arguments, function( elem ) {
			if ( this.parentNode ) {
				this.parentNode.insertBefore( elem, this );
			}
		} );
	},

	after: function() {
		return domManip( this, arguments, function( elem ) {
			if ( this.parentNode ) {
				this.parentNode.insertBefore( elem, this.nextSibling );
			}
		} );
	},

	empty: function() {
		var elem,
			i = 0;

		for ( ; ( elem = this[ i ] ) != null; i++ ) {
			if ( elem.nodeType === 1 ) {

				// Prevent memory leaks
				jQuery.cleanData( getAll( elem, false ) );

				// Remove any remaining nodes
				elem.textContent = "";
			}
		}

		return this;
	},

	clone: function( dataAndEvents, deepDataAndEvents ) {
		dataAndEvents = dataAndEvents == null ? false : dataAndEvents;
		deepDataAndEvents = deepDataAndEvents == null ? dataAndEvents : deepDataAndEvents;

		return this.map( function() {
			return jQuery.clone( this, dataAndEvents, deepDataAndEvents );
		} );
	},

	html: function( value ) {
		return access( this, function( value ) {
			var elem = this[ 0 ] || {},
				i = 0,
				l = this.length;

			if ( value === undefined && elem.nodeType === 1 ) {
				return elem.innerHTML;
			}

			// See if we can take a shortcut and just use innerHTML
			if ( typeof value === "string" && !rnoInnerhtml.test( value ) &&
				!wrapMap[ ( rtagName.exec( value ) || [ "", "" ] )[ 1 ].toLowerCase() ] ) {

				value = jQuery.htmlPrefilter( value );

				try {
					for ( ; i < l; i++ ) {
						elem = this[ i ] || {};

						// Remove element nodes and prevent memory leaks
						if ( elem.nodeType === 1 ) {
							jQuery.cleanData( getAll( elem, false ) );
							elem.innerHTML = value;
						}
					}

					elem = 0;

				// If using innerHTML throws an exception, use the fallback method
				} catch ( e ) {}
			}

			if ( elem ) {
				this.empty().append( value );
			}
		}, null, value, arguments.length );
	},

	replaceWith: function() {
		var ignored = [];

		// Make the changes, replacing each non-ignored context element with the new content
		return domManip( this, arguments, function( elem ) {
			var parent = this.parentNode;

			if ( jQuery.inArray( this, ignored ) < 0 ) {
				jQuery.cleanData( getAll( this ) );
				if ( parent ) {
					parent.replaceChild( elem, this );
				}
			}

		// Force callback invocation
		}, ignored );
	}
} );

jQuery.each( {
	appendTo: "append",
	prependTo: "prepend",
	insertBefore: "before",
	insertAfter: "after",
	replaceAll: "replaceWith"
}, function( name, original ) {
	jQuery.fn[ name ] = function( selector ) {
		var elems,
			ret = [],
			insert = jQuery( selector ),
			last = insert.length - 1,
			i = 0;

		for ( ; i <= last; i++ ) {
			elems = i === last ? this : this.clone( true );
			jQuery( insert[ i ] )[ original ]( elems );

			// Support: Android <=4.0 only, PhantomJS 1 only
			// .get() because push.apply(_, arraylike) throws on ancient WebKit
			push.apply( ret, elems.get() );
		}

		return this.pushStack( ret );
	};
} );
var rnumnonpx = new RegExp( "^(" + pnum + ")(?!px)[a-z%]+$", "i" );

var getStyles = function( elem ) {

		// Support: IE <=11 only, Firefox <=30 (#15098, #14150)
		// IE throws on elements created in popups
		// FF meanwhile throws on frame elements through "defaultView.getComputedStyle"
		var view = elem.ownerDocument.defaultView;

		if ( !view || !view.opener ) {
			view = window;
		}

		return view.getComputedStyle( elem );
	};

var swap = function( elem, options, callback ) {
	var ret, name,
		old = {};

	// Remember the old values, and insert the new ones
	for ( name in options ) {
		old[ name ] = elem.style[ name ];
		elem.style[ name ] = options[ name ];
	}

	ret = callback.call( elem );

	// Revert the old values
	for ( name in options ) {
		elem.style[ name ] = old[ name ];
	}

	return ret;
};


var rboxStyle = new RegExp( cssExpand.join( "|" ), "i" );



( function() {

	// Executing both pixelPosition & boxSizingReliable tests require only one layout
	// so they're executed at the same time to save the second computation.
	function computeStyleTests() {

		// This is a singleton, we need to execute it only once
		if ( !div ) {
			return;
		}

		container.style.cssText = "position:absolute;left:-11111px;width:60px;" +
			"margin-top:1px;padding:0;border:0";
		div.style.cssText =
			"position:relative;display:block;box-sizing:border-box;overflow:scroll;" +
			"margin:auto;border:1px;padding:1px;" +
			"width:60%;top:1%";
		documentElement.appendChild( container ).appendChild( div );

		var divStyle = window.getComputedStyle( div );
		pixelPositionVal = divStyle.top !== "1%";

		// Support: Android 4.0 - 4.3 only, Firefox <=3 - 44
		reliableMarginLeftVal = roundPixelMeasures( divStyle.marginLeft ) === 12;

		// Support: Android 4.0 - 4.3 only, Safari <=9.1 - 10.1, iOS <=7.0 - 9.3
		// Some styles come back with percentage values, even though they shouldn't
		div.style.right = "60%";
		pixelBoxStylesVal = roundPixelMeasures( divStyle.right ) === 36;

		// Support: IE 9 - 11 only
		// Detect misreporting of content dimensions for box-sizing:border-box elements
		boxSizingReliableVal = roundPixelMeasures( divStyle.width ) === 36;

		// Support: IE 9 only
		// Detect overflow:scroll screwiness (gh-3699)
		// Support: Chrome <=64
		// Don't get tricked when zoom affects offsetWidth (gh-4029)
		div.style.position = "absolute";
		scrollboxSizeVal = roundPixelMeasures( div.offsetWidth / 3 ) === 12;

		documentElement.removeChild( container );

		// Nullify the div so it wouldn't be stored in the memory and
		// it will also be a sign that checks already performed
		div = null;
	}

	function roundPixelMeasures( measure ) {
		return Math.round( parseFloat( measure ) );
	}

	var pixelPositionVal, boxSizingReliableVal, scrollboxSizeVal, pixelBoxStylesVal,
		reliableTrDimensionsVal, reliableMarginLeftVal,
		container = document.createElement( "div" ),
		div = document.createElement( "div" );

	// Finish early in limited (non-browser) environments
	if ( !div.style ) {
		return;
	}

	// Support: IE <=9 - 11 only
	// Style of cloned element affects source element cloned (#8908)
	div.style.backgroundClip = "content-box";
	div.cloneNode( true ).style.backgroundClip = "";
	support.clearCloneStyle = div.style.backgroundClip === "content-box";

	jQuery.extend( support, {
		boxSizingReliable: function() {
			computeStyleTests();
			return boxSizingReliableVal;
		},
		pixelBoxStyles: function() {
			computeStyleTests();
			return pixelBoxStylesVal;
		},
		pixelPosition: function() {
			computeStyleTests();
			return pixelPositionVal;
		},
		reliableMarginLeft: function() {
			computeStyleTests();
			return reliableMarginLeftVal;
		},
		scrollboxSize: function() {
			computeStyleTests();
			return scrollboxSizeVal;
		},

		// Support: IE 9 - 11+, Edge 15 - 18+
		// IE/Edge misreport `getComputedStyle` of table rows with width/height
		// set in CSS while `offset*` properties report correct values.
		// Behavior in IE 9 is more subtle than in newer versions & it passes
		// some versions of this test; make sure not to make it pass there!
		//
		// Support: Firefox 70+
		// Only Firefox includes border widths
		// in computed dimensions. (gh-4529)
		reliableTrDimensions: function() {
			var table, tr, trChild, trStyle;
			if ( reliableTrDimensionsVal == null ) {
				table = document.createElement( "table" );
				tr = document.createElement( "tr" );
				trChild = document.createElement( "div" );

				table.style.cssText = "position:absolute;left:-11111px;border-collapse:separate";
				tr.style.cssText = "border:1px solid";

				// Support: Chrome 86+
				// Height set through cssText does not get applied.
				// Computed height then comes back as 0.
				tr.style.height = "1px";
				trChild.style.height = "9px";

				// Support: Android 8 Chrome 86+
				// In our bodyBackground.html iframe,
				// display for all div elements is set to "inline",
				// which causes a problem only in Android 8 Chrome 86.
				// Ensuring the div is display: block
				// gets around this issue.
				trChild.style.display = "block";

				documentElement
					.appendChild( table )
					.appendChild( tr )
					.appendChild( trChild );

				trStyle = window.getComputedStyle( tr );
				reliableTrDimensionsVal = ( parseInt( trStyle.height, 10 ) +
					parseInt( trStyle.borderTopWidth, 10 ) +
					parseInt( trStyle.borderBottomWidth, 10 ) ) === tr.offsetHeight;

				documentElement.removeChild( table );
			}
			return reliableTrDimensionsVal;
		}
	} );
} )();


function curCSS( elem, name, computed ) {
	var width, minWidth, maxWidth, ret,

		// Support: Firefox 51+
		// Retrieving style before computed somehow
		// fixes an issue with getting wrong values
		// on detached elements
		style = elem.style;

	computed = computed || getStyles( elem );

	// getPropertyValue is needed for:
	//   .css('filter') (IE 9 only, #12537)
	//   .css('--customProperty) (#3144)
	if ( computed ) {
		ret = computed.getPropertyValue( name ) || computed[ name ];

		if ( ret === "" && !isAttached( elem ) ) {
			ret = jQuery.style( elem, name );
		}

		// A tribute to the "awesome hack by Dean Edwards"
		// Android Browser returns percentage for some values,
		// but width seems to be reliably pixels.
		// This is against the CSSOM draft spec:
		// https://drafts.csswg.org/cssom/#resolved-values
		if ( !support.pixelBoxStyles() && rnumnonpx.test( ret ) && rboxStyle.test( name ) ) {

			// Remember the original values
			width = style.width;
			minWidth = style.minWidth;
			maxWidth = style.maxWidth;

			// Put in the new values to get a computed value out
			style.minWidth = style.maxWidth = style.width = ret;
			ret = computed.width;

			// Revert the changed values
			style.width = width;
			style.minWidth = minWidth;
			style.maxWidth = maxWidth;
		}
	}

	return ret !== undefined ?

		// Support: IE <=9 - 11 only
		// IE returns zIndex value as an integer.
		ret + "" :
		ret;
}


function addGetHookIf( conditionFn, hookFn ) {

	// Define the hook, we'll check on the first run if it's really needed.
	return {
		get: function() {
			if ( conditionFn() ) {

				// Hook not needed (or it's not possible to use it due
				// to missing dependency), remove it.
				delete this.get;
				return;
			}

			// Hook needed; redefine it so that the support test is not executed again.
			return ( this.get = hookFn ).apply( this, arguments );
		}
	};
}


var cssPrefixes = [ "Webkit", "Moz", "ms" ],
	emptyStyle = document.createElement( "div" ).style,
	vendorProps = {};

// Return a vendor-prefixed property or undefined
function vendorPropName( name ) {

	// Check for vendor prefixed names
	var capName = name[ 0 ].toUpperCase() + name.slice( 1 ),
		i = cssPrefixes.length;

	while ( i-- ) {
		name = cssPrefixes[ i ] + capName;
		if ( name in emptyStyle ) {
			return name;
		}
	}
}

// Return a potentially-mapped jQuery.cssProps or vendor prefixed property
function finalPropName( name ) {
	var final = jQuery.cssProps[ name ] || vendorProps[ name ];

	if ( final ) {
		return final;
	}
	if ( name in emptyStyle ) {
		return name;
	}
	return vendorProps[ name ] = vendorPropName( name ) || name;
}


var

	// Swappable if display is none or starts with table
	// except "table", "table-cell", or "table-caption"
	// See here for display values: https://developer.mozilla.org/en-US/docs/CSS/display
	rdisplayswap = /^(none|table(?!-c[ea]).+)/,
	rcustomProp = /^--/,
	cssShow = { position: "absolute", visibility: "hidden", display: "block" },
	cssNormalTransform = {
		letterSpacing: "0",
		fontWeight: "400"
	};

function setPositiveNumber( _elem, value, subtract ) {

	// Any relative (+/-) values have already been
	// normalized at this point
	var matches = rcssNum.exec( value );
	return matches ?

		// Guard against undefined "subtract", e.g., when used as in cssHooks
		Math.max( 0, matches[ 2 ] - ( subtract || 0 ) ) + ( matches[ 3 ] || "px" ) :
		value;
}

function boxModelAdjustment( elem, dimension, box, isBorderBox, styles, computedVal ) {
	var i = dimension === "width" ? 1 : 0,
		extra = 0,
		delta = 0;

	// Adjustment may not be necessary
	if ( box === ( isBorderBox ? "border" : "content" ) ) {
		return 0;
	}

	for ( ; i < 4; i += 2 ) {

		// Both box models exclude margin
		if ( box === "margin" ) {
			delta += jQuery.css( elem, box + cssExpand[ i ], true, styles );
		}

		// If we get here with a content-box, we're seeking "padding" or "border" or "margin"
		if ( !isBorderBox ) {

			// Add padding
			delta += jQuery.css( elem, "padding" + cssExpand[ i ], true, styles );

			// For "border" or "margin", add border
			if ( box !== "padding" ) {
				delta += jQuery.css( elem, "border" + cssExpand[ i ] + "Width", true, styles );

			// But still keep track of it otherwise
			} else {
				extra += jQuery.css( elem, "border" + cssExpand[ i ] + "Width", true, styles );
			}

		// If we get here with a border-box (content + padding + border), we're seeking "content" or
		// "padding" or "margin"
		} else {

			// For "content", subtract padding
			if ( box === "content" ) {
				delta -= jQuery.css( elem, "padding" + cssExpand[ i ], true, styles );
			}

			// For "content" or "padding", subtract border
			if ( box !== "margin" ) {
				delta -= jQuery.css( elem, "border" + cssExpand[ i ] + "Width", true, styles );
			}
		}
	}

	// Account for positive content-box scroll gutter when requested by providing computedVal
	if ( !isBorderBox && computedVal >= 0 ) {

		// offsetWidth/offsetHeight is a rounded sum of content, padding, scroll gutter, and border
		// Assuming integer scroll gutter, subtract the rest and round down
		delta += Math.max( 0, Math.ceil(
			elem[ "offset" + dimension[ 0 ].toUpperCase() + dimension.slice( 1 ) ] -
			computedVal -
			delta -
			extra -
			0.5

		// If offsetWidth/offsetHeight is unknown, then we can't determine content-box scroll gutter
		// Use an explicit zero to avoid NaN (gh-3964)
		) ) || 0;
	}

	return delta;
}

function getWidthOrHeight( elem, dimension, extra ) {

	// Start with computed style
	var styles = getStyles( elem ),

		// To avoid forcing a reflow, only fetch boxSizing if we need it (gh-4322).
		// Fake content-box until we know it's needed to know the true value.
		boxSizingNeeded = !support.boxSizingReliable() || extra,
		isBorderBox = boxSizingNeeded &&
			jQuery.css( elem, "boxSizing", false, styles ) === "border-box",
		valueIsBorderBox = isBorderBox,

		val = curCSS( elem, dimension, styles ),
		offsetProp = "offset" + dimension[ 0 ].toUpperCase() + dimension.slice( 1 );

	// Support: Firefox <=54
	// Return a confounding non-pixel value or feign ignorance, as appropriate.
	if ( rnumnonpx.test( val ) ) {
		if ( !extra ) {
			return val;
		}
		val = "auto";
	}


	// Support: IE 9 - 11 only
	// Use offsetWidth/offsetHeight for when box sizing is unreliable.
	// In those cases, the computed value can be trusted to be border-box.
	if ( ( !support.boxSizingReliable() && isBorderBox ||

		// Support: IE 10 - 11+, Edge 15 - 18+
		// IE/Edge misreport `getComputedStyle` of table rows with width/height
		// set in CSS while `offset*` properties report correct values.
		// Interestingly, in some cases IE 9 doesn't suffer from this issue.
		!support.reliableTrDimensions() && nodeName( elem, "tr" ) ||

		// Fall back to offsetWidth/offsetHeight when value is "auto"
		// This happens for inline elements with no explicit setting (gh-3571)
		val === "auto" ||

		// Support: Android <=4.1 - 4.3 only
		// Also use offsetWidth/offsetHeight for misreported inline dimensions (gh-3602)
		!parseFloat( val ) && jQuery.css( elem, "display", false, styles ) === "inline" ) &&

		// Make sure the element is visible & connected
		elem.getClientRects().length ) {

		isBorderBox = jQuery.css( elem, "boxSizing", false, styles ) === "border-box";

		// Where available, offsetWidth/offsetHeight approximate border box dimensions.
		// Where not available (e.g., SVG), assume unreliable box-sizing and interpret the
		// retrieved value as a content box dimension.
		valueIsBorderBox = offsetProp in elem;
		if ( valueIsBorderBox ) {
			val = elem[ offsetProp ];
		}
	}

	// Normalize "" and auto
	val = parseFloat( val ) || 0;

	// Adjust for the element's box model
	return ( val +
		boxModelAdjustment(
			elem,
			dimension,
			extra || ( isBorderBox ? "border" : "content" ),
			valueIsBorderBox,
			styles,

			// Provide the current computed size to request scroll gutter calculation (gh-3589)
			val
		)
	) + "px";
}

jQuery.extend( {

	// Add in style property hooks for overriding the default
	// behavior of getting and setting a style property
	cssHooks: {
		opacity: {
			get: function( elem, computed ) {
				if ( computed ) {

					// We should always get a number back from opacity
					var ret = curCSS( elem, "opacity" );
					return ret === "" ? "1" : ret;
				}
			}
		}
	},

	// Don't automatically add "px" to these possibly-unitless properties
	cssNumber: {
		"animationIterationCount": true,
		"columnCount": true,
		"fillOpacity": true,
		"flexGrow": true,
		"flexShrink": true,
		"fontWeight": true,
		"gridArea": true,
		"gridColumn": true,
		"gridColumnEnd": true,
		"gridColumnStart": true,
		"gridRow": true,
		"gridRowEnd": true,
		"gridRowStart": true,
		"lineHeight": true,
		"opacity": true,
		"order": true,
		"orphans": true,
		"widows": true,
		"zIndex": true,
		"zoom": true
	},

	// Add in properties whose names you wish to fix before
	// setting or getting the value
	cssProps: {},

	// Get and set the style property on a DOM Node
	style: function( elem, name, value, extra ) {

		// Don't set styles on text and comment nodes
		if ( !elem || elem.nodeType === 3 || elem.nodeType === 8 || !elem.style ) {
			return;
		}

		// Make sure that we're working with the right name
		var ret, type, hooks,
			origName = camelCase( name ),
			isCustomProp = rcustomProp.test( name ),
			style = elem.style;

		// Make sure that we're working with the right name. We don't
		// want to query the value if it is a CSS custom property
		// since they are user-defined.
		if ( !isCustomProp ) {
			name = finalPropName( origName );
		}

		// Gets hook for the prefixed version, then unprefixed version
		hooks = jQuery.cssHooks[ name ] || jQuery.cssHooks[ origName ];

		// Check if we're setting a value
		if ( value !== undefined ) {
			type = typeof value;

			// Convert "+=" or "-=" to relative numbers (#7345)
			if ( type === "string" && ( ret = rcssNum.exec( value ) ) && ret[ 1 ] ) {
				value = adjustCSS( elem, name, ret );

				// Fixes bug #9237
				type = "number";
			}

			// Make sure that null and NaN values aren't set (#7116)
			if ( value == null || value !== value ) {
				return;
			}

			// If a number was passed in, add the unit (except for certain CSS properties)
			// The isCustomProp check can be removed in jQuery 4.0 when we only auto-append
			// "px" to a few hardcoded values.
			if ( type === "number" && !isCustomProp ) {
				value += ret && ret[ 3 ] || ( jQuery.cssNumber[ origName ] ? "" : "px" );
			}

			// background-* props affect original clone's values
			if ( !support.clearCloneStyle && value === "" && name.indexOf( "background" ) === 0 ) {
				style[ name ] = "inherit";
			}

			// If a hook was provided, use that value, otherwise just set the specified value
			if ( !hooks || !( "set" in hooks ) ||
				( value = hooks.set( elem, value, extra ) ) !== undefined ) {

				if ( isCustomProp ) {
					style.setProperty( name, value );
				} else {
					style[ name ] = value;
				}
			}

		} else {

			// If a hook was provided get the non-computed value from there
			if ( hooks && "get" in hooks &&
				( ret = hooks.get( elem, false, extra ) ) !== undefined ) {

				return ret;
			}

			// Otherwise just get the value from the style object
			return style[ name ];
		}
	},

	css: function( elem, name, extra, styles ) {
		var val, num, hooks,
			origName = camelCase( name ),
			isCustomProp = rcustomProp.test( name );

		// Make sure that we're working with the right name. We don't
		// want to modify the value if it is a CSS custom property
		// since they are user-defined.
		if ( !isCustomProp ) {
			name = finalPropName( origName );
		}

		// Try prefixed name followed by the unprefixed name
		hooks = jQuery.cssHooks[ name ] || jQuery.cssHooks[ origName ];

		// If a hook was provided get the computed value from there
		if ( hooks && "get" in hooks ) {
			val = hooks.get( elem, true, extra );
		}

		// Otherwise, if a way to get the computed value exists, use that
		if ( val === undefined ) {
			val = curCSS( elem, name, styles );
		}

		// Convert "normal" to computed value
		if ( val === "normal" && name in cssNormalTransform ) {
			val = cssNormalTransform[ name ];
		}

		// Make numeric if forced or a qualifier was provided and val looks numeric
		if ( extra === "" || extra ) {
			num = parseFloat( val );
			return extra === true || isFinite( num ) ? num || 0 : val;
		}

		return val;
	}
} );

jQuery.each( [ "height", "width" ], function( _i, dimension ) {
	jQuery.cssHooks[ dimension ] = {
		get: function( elem, computed, extra ) {
			if ( computed ) {

				// Certain elements can have dimension info if we invisibly show them
				// but it must have a current display style that would benefit
				return rdisplayswap.test( jQuery.css( elem, "display" ) ) &&

					// Support: Safari 8+
					// Table columns in Safari have non-zero offsetWidth & zero
					// getBoundingClientRect().width unless display is changed.
					// Support: IE <=11 only
					// Running getBoundingClientRect on a disconnected node
					// in IE throws an error.
					( !elem.getClientRects().length || !elem.getBoundingClientRect().width ) ?
					swap( elem, cssShow, function() {
						return getWidthOrHeight( elem, dimension, extra );
					} ) :
					getWidthOrHeight( elem, dimension, extra );
			}
		},

		set: function( elem, value, extra ) {
			var matches,
				styles = getStyles( elem ),

				// Only read styles.position if the test has a chance to fail
				// to avoid forcing a reflow.
				scrollboxSizeBuggy = !support.scrollboxSize() &&
					styles.position === "absolute",

				// To avoid forcing a reflow, only fetch boxSizing if we need it (gh-3991)
				boxSizingNeeded = scrollboxSizeBuggy || extra,
				isBorderBox = boxSizingNeeded &&
					jQuery.css( elem, "boxSizing", false, styles ) === "border-box",
				subtract = extra ?
					boxModelAdjustment(
						elem,
						dimension,
						extra,
						isBorderBox,
						styles
					) :
					0;

			// Account for unreliable border-box dimensions by comparing offset* to computed and
			// faking a content-box to get border and padding (gh-3699)
			if ( isBorderBox && scrollboxSizeBuggy ) {
				subtract -= Math.ceil(
					elem[ "offset" + dimension[ 0 ].toUpperCase() + dimension.slice( 1 ) ] -
					parseFloat( styles[ dimension ] ) -
					boxModelAdjustment( elem, dimension, "border", false, styles ) -
					0.5
				);
			}

			// Convert to pixels if value adjustment is needed
			if ( subtract && ( matches = rcssNum.exec( value ) ) &&
				( matches[ 3 ] || "px" ) !== "px" ) {

				elem.style[ dimension ] = value;
				value = jQuery.css( elem, dimension );
			}

			return setPositiveNumber( elem, value, subtract );
		}
	};
} );

jQuery.cssHooks.marginLeft = addGetHookIf( support.reliableMarginLeft,
	function( elem, computed ) {
		if ( computed ) {
			return ( parseFloat( curCSS( elem, "marginLeft" ) ) ||
				elem.getBoundingClientRect().left -
					swap( elem, { marginLeft: 0 }, function() {
						return elem.getBoundingClientRect().left;
					} )
			) + "px";
		}
	}
);

// These hooks are used by animate to expand properties
jQuery.each( {
	margin: "",
	padding: "",
	border: "Width"
}, function( prefix, suffix ) {
	jQuery.cssHooks[ prefix + suffix ] = {
		expand: function( value ) {
			var i = 0,
				expanded = {},

				// Assumes a single number if not a string
				parts = typeof value === "string" ? value.split( " " ) : [ value ];

			for ( ; i < 4; i++ ) {
				expanded[ prefix + cssExpand[ i ] + suffix ] =
					parts[ i ] || parts[ i - 2 ] || parts[ 0 ];
			}

			return expanded;
		}
	};

	if ( prefix !== "margin" ) {
		jQuery.cssHooks[ prefix + suffix ].set = setPositiveNumber;
	}
} );

jQuery.fn.extend( {
	css: function( name, value ) {
		return access( this, function( elem, name, value ) {
			var styles, len,
				map = {},
				i = 0;

			if ( Array.isArray( name ) ) {
				styles = getStyles( elem );
				len = name.length;

				for ( ; i < len; i++ ) {
					map[ name[ i ] ] = jQuery.css( elem, name[ i ], false, styles );
				}

				return map;
			}

			return value !== undefined ?
				jQuery.style( elem, name, value ) :
				jQuery.css( elem, name );
		}, name, value, arguments.length > 1 );
	}
} );


function Tween( elem, options, prop, end, easing ) {
	return new Tween.prototype.init( elem, options, prop, end, easing );
}
jQuery.Tween = Tween;

Tween.prototype = {
	constructor: Tween,
	init: function( elem, options, prop, end, easing, unit ) {
		this.elem = elem;
		this.prop = prop;
		this.easing = easing || jQuery.easing._default;
		this.options = options;
		this.start = this.now = this.cur();
		this.end = end;
		this.unit = unit || ( jQuery.cssNumber[ prop ] ? "" : "px" );
	},
	cur: function() {
		var hooks = Tween.propHooks[ this.prop ];

		return hooks && hooks.get ?
			hooks.get( this ) :
			Tween.propHooks._default.get( this );
	},
	run: function( percent ) {
		var eased,
			hooks = Tween.propHooks[ this.prop ];

		if ( this.options.duration ) {
			this.pos = eased = jQuery.easing[ this.easing ](
				percent, this.options.duration * percent, 0, 1, this.options.duration
			);
		} else {
			this.pos = eased = percent;
		}
		this.now = ( this.end - this.start ) * eased + this.start;

		if ( this.options.step ) {
			this.options.step.call( this.elem, this.now, this );
		}

		if ( hooks && hooks.set ) {
			hooks.set( this );
		} else {
			Tween.propHooks._default.set( this );
		}
		return this;
	}
};

Tween.prototype.init.prototype = Tween.prototype;

Tween.propHooks = {
	_default: {
		get: function( tween ) {
			var result;

			// Use a property on the element directly when it is not a DOM element,
			// or when there is no matching style property that exists.
			if ( tween.elem.nodeType !== 1 ||
				tween.elem[ tween.prop ] != null && tween.elem.style[ tween.prop ] == null ) {
				return tween.elem[ tween.prop ];
			}

			// Passing an empty string as a 3rd parameter to .css will automatically
			// attempt a parseFloat and fallback to a string if the parse fails.
			// Simple values such as "10px" are parsed to Float;
			// complex values such as "rotate(1rad)" are returned as-is.
			result = jQuery.css( tween.elem, tween.prop, "" );

			// Empty strings, null, undefined and "auto" are converted to 0.
			return !result || result === "auto" ? 0 : result;
		},
		set: function( tween ) {

			// Use step hook for back compat.
			// Use cssHook if its there.
			// Use .style if available and use plain properties where available.
			if ( jQuery.fx.step[ tween.prop ] ) {
				jQuery.fx.step[ tween.prop ]( tween );
			} else if ( tween.elem.nodeType === 1 && (
				jQuery.cssHooks[ tween.prop ] ||
					tween.elem.style[ finalPropName( tween.prop ) ] != null ) ) {
				jQuery.style( tween.elem, tween.prop, tween.now + tween.unit );
			} else {
				tween.elem[ tween.prop ] = tween.now;
			}
		}
	}
};

// Support: IE <=9 only
// Panic based approach to setting things on disconnected nodes
Tween.propHooks.scrollTop = Tween.propHooks.scrollLeft = {
	set: function( tween ) {
		if ( tween.elem.nodeType && tween.elem.parentNode ) {
			tween.elem[ tween.prop ] = tween.now;
		}
	}
};

jQuery.easing = {
	linear: function( p ) {
		return p;
	},
	swing: function( p ) {
		return 0.5 - Math.cos( p * Math.PI ) / 2;
	},
	_default: "swing"
};

jQuery.fx = Tween.prototype.init;

// Back compat <1.8 extension point
jQuery.fx.step = {};




var
	fxNow, inProgress,
	rfxtypes = /^(?:toggle|show|hide)$/,
	rrun = /queueHooks$/;

function schedule() {
	if ( inProgress ) {
		if ( document.hidden === false && window.requestAnimationFrame ) {
			window.requestAnimationFrame( schedule );
		} else {
			window.setTimeout( schedule, jQuery.fx.interval );
		}

		jQuery.fx.tick();
	}
}

// Animations created synchronously will run synchronously
function createFxNow() {
	window.setTimeout( function() {
		fxNow = undefined;
	} );
	return ( fxNow = Date.now() );
}

// Generate parameters to create a standard animation
function genFx( type, includeWidth ) {
	var which,
		i = 0,
		attrs = { height: type };

	// If we include width, step value is 1 to do all cssExpand values,
	// otherwise step value is 2 to skip over Left and Right
	includeWidth = includeWidth ? 1 : 0;
	for ( ; i < 4; i += 2 - includeWidth ) {
		which = cssExpand[ i ];
		attrs[ "margin" + which ] = attrs[ "padding" + which ] = type;
	}

	if ( includeWidth ) {
		attrs.opacity = attrs.width = type;
	}

	return attrs;
}

function createTween( value, prop, animation ) {
	var tween,
		collection = ( Animation.tweeners[ prop ] || [] ).concat( Animation.tweeners[ "*" ] ),
		index = 0,
		length = collection.length;
	for ( ; index < length; index++ ) {
		if ( ( tween = collection[ index ].call( animation, prop, value ) ) ) {

			// We're done with this property
			return tween;
		}
	}
}

function defaultPrefilter( elem, props, opts ) {
	var prop, value, toggle, hooks, oldfire, propTween, restoreDisplay, display,
		isBox = "width" in props || "height" in props,
		anim = this,
		orig = {},
		style = elem.style,
		hidden = elem.nodeType && isHiddenWithinTree( elem ),
		dataShow = dataPriv.get( elem, "fxshow" );

	// Queue-skipping animations hijack the fx hooks
	if ( !opts.queue ) {
		hooks = jQuery._queueHooks( elem, "fx" );
		if ( hooks.unqueued == null ) {
			hooks.unqueued = 0;
			oldfire = hooks.empty.fire;
			hooks.empty.fire = function() {
				if ( !hooks.unqueued ) {
					oldfire();
				}
			};
		}
		hooks.unqueued++;

		anim.always( function() {

			// Ensure the complete handler is called before this completes
			anim.always( function() {
				hooks.unqueued--;
				if ( !jQuery.queue( elem, "fx" ).length ) {
					hooks.empty.fire();
				}
			} );
		} );
	}

	// Detect show/hide animations
	for ( prop in props ) {
		value = props[ prop ];
		if ( rfxtypes.test( value ) ) {
			delete props[ prop ];
			toggle = toggle || value === "toggle";
			if ( value === ( hidden ? "hide" : "show" ) ) {

				// Pretend to be hidden if this is a "show" and
				// there is still data from a stopped show/hide
				if ( value === "show" && dataShow && dataShow[ prop ] !== undefined ) {
					hidden = true;

				// Ignore all other no-op show/hide data
				} else {
					continue;
				}
			}
			orig[ prop ] = dataShow && dataShow[ prop ] || jQuery.style( elem, prop );
		}
	}

	// Bail out if this is a no-op like .hide().hide()
	propTween = !jQuery.isEmptyObject( props );
	if ( !propTween && jQuery.isEmptyObject( orig ) ) {
		return;
	}

	// Restrict "overflow" and "display" styles during box animations
	if ( isBox && elem.nodeType === 1 ) {

		// Support: IE <=9 - 11, Edge 12 - 15
		// Record all 3 overflow attributes because IE does not infer the shorthand
		// from identically-valued overflowX and overflowY and Edge just mirrors
		// the overflowX value there.
		opts.overflow = [ style.overflow, style.overflowX, style.overflowY ];

		// Identify a display type, preferring old show/hide data over the CSS cascade
		restoreDisplay = dataShow && dataShow.display;
		if ( restoreDisplay == null ) {
			restoreDisplay = dataPriv.get( elem, "display" );
		}
		display = jQuery.css( elem, "display" );
		if ( display === "none" ) {
			if ( restoreDisplay ) {
				display = restoreDisplay;
			} else {

				// Get nonempty value(s) by temporarily forcing visibility
				showHide( [ elem ], true );
				restoreDisplay = elem.style.display || restoreDisplay;
				display = jQuery.css( elem, "display" );
				showHide( [ elem ] );
			}
		}

		// Animate inline elements as inline-block
		if ( display === "inline" || display === "inline-block" && restoreDisplay != null ) {
			if ( jQuery.css( elem, "float" ) === "none" ) {

				// Restore the original display value at the end of pure show/hide animations
				if ( !propTween ) {
					anim.done( function() {
						style.display = restoreDisplay;
					} );
					if ( restoreDisplay == null ) {
						display = style.display;
						restoreDisplay = display === "none" ? "" : display;
					}
				}
				style.display = "inline-block";
			}
		}
	}

	if ( opts.overflow ) {
		style.overflow = "hidden";
		anim.always( function() {
			style.overflow = opts.overflow[ 0 ];
			style.overflowX = opts.overflow[ 1 ];
			style.overflowY = opts.overflow[ 2 ];
		} );
	}

	// Implement show/hide animations
	propTween = false;
	for ( prop in orig ) {

		// General show/hide setup for this element animation
		if ( !propTween ) {
			if ( dataShow ) {
				if ( "hidden" in dataShow ) {
					hidden = dataShow.hidden;
				}
			} else {
				dataShow = dataPriv.access( elem, "fxshow", { display: restoreDisplay } );
			}

			// Store hidden/visible for toggle so `.stop().toggle()` "reverses"
			if ( toggle ) {
				dataShow.hidden = !hidden;
			}

			// Show elements before animating them
			if ( hidden ) {
				showHide( [ elem ], true );
			}

			/* eslint-disable no-loop-func */

			anim.done( function() {

				/* eslint-enable no-loop-func */

				// The final step of a "hide" animation is actually hiding the element
				if ( !hidden ) {
					showHide( [ elem ] );
				}
				dataPriv.remove( elem, "fxshow" );
				for ( prop in orig ) {
					jQuery.style( elem, prop, orig[ prop ] );
				}
			} );
		}

		// Per-property setup
		propTween = createTween( hidden ? dataShow[ prop ] : 0, prop, anim );
		if ( !( prop in dataShow ) ) {
			dataShow[ prop ] = propTween.start;
			if ( hidden ) {
				propTween.end = propTween.start;
				propTween.start = 0;
			}
		}
	}
}

function propFilter( props, specialEasing ) {
	var index, name, easing, value, hooks;

	// camelCase, specialEasing and expand cssHook pass
	for ( index in props ) {
		name = camelCase( index );
		easing = specialEasing[ name ];
		value = props[ index ];
		if ( Array.isArray( value ) ) {
			easing = value[ 1 ];
			value = props[ index ] = value[ 0 ];
		}

		if ( index !== name ) {
			props[ name ] = value;
			delete props[ index ];
		}

		hooks = jQuery.cssHooks[ name ];
		if ( hooks && "expand" in hooks ) {
			value = hooks.expand( value );
			delete props[ name ];

			// Not quite $.extend, this won't overwrite existing keys.
			// Reusing 'index' because we have the correct "name"
			for ( index in value ) {
				if ( !( index in props ) ) {
					props[ index ] = value[ index ];
					specialEasing[ index ] = easing;
				}
			}
		} else {
			specialEasing[ name ] = easing;
		}
	}
}

function Animation( elem, properties, options ) {
	var result,
		stopped,
		index = 0,
		length = Animation.prefilters.length,
		deferred = jQuery.Deferred().always( function() {

			// Don't match elem in the :animated selector
			delete tick.elem;
		} ),
		tick = function() {
			if ( stopped ) {
				return false;
			}
			var currentTime = fxNow || createFxNow(),
				remaining = Math.max( 0, animation.startTime + animation.duration - currentTime ),

				// Support: Android 2.3 only
				// Archaic crash bug won't allow us to use `1 - ( 0.5 || 0 )` (#12497)
				temp = remaining / animation.duration || 0,
				percent = 1 - temp,
				index = 0,
				length = animation.tweens.length;

			for ( ; index < length; index++ ) {
				animation.tweens[ index ].run( percent );
			}

			deferred.notifyWith( elem, [ animation, percent, remaining ] );

			// If there's more to do, yield
			if ( percent < 1 && length ) {
				return remaining;
			}

			// If this was an empty animation, synthesize a final progress notification
			if ( !length ) {
				deferred.notifyWith( elem, [ animation, 1, 0 ] );
			}

			// Resolve the animation and report its conclusion
			deferred.resolveWith( elem, [ animation ] );
			return false;
		},
		animation = deferred.promise( {
			elem: elem,
			props: jQuery.extend( {}, properties ),
			opts: jQuery.extend( true, {
				specialEasing: {},
				easing: jQuery.easing._default
			}, options ),
			originalProperties: properties,
			originalOptions: options,
			startTime: fxNow || createFxNow(),
			duration: options.duration,
			tweens: [],
			createTween: function( prop, end ) {
				var tween = jQuery.Tween( elem, animation.opts, prop, end,
					animation.opts.specialEasing[ prop ] || animation.opts.easing );
				animation.tweens.push( tween );
				return tween;
			},
			stop: function( gotoEnd ) {
				var index = 0,

					// If we are going to the end, we want to run all the tweens
					// otherwise we skip this part
					length = gotoEnd ? animation.tweens.length : 0;
				if ( stopped ) {
					return this;
				}
				stopped = true;
				for ( ; index < length; index++ ) {
					animation.tweens[ index ].run( 1 );
				}

				// Resolve when we played the last frame; otherwise, reject
				if ( gotoEnd ) {
					deferred.notifyWith( elem, [ animation, 1, 0 ] );
					deferred.resolveWith( elem, [ animation, gotoEnd ] );
				} else {
					deferred.rejectWith( elem, [ animation, gotoEnd ] );
				}
				return this;
			}
		} ),
		props = animation.props;

	propFilter( props, animation.opts.specialEasing );

	for ( ; index < length; index++ ) {
		result = Animation.prefilters[ index ].call( animation, elem, props, animation.opts );
		if ( result ) {
			if ( isFunction( result.stop ) ) {
				jQuery._queueHooks( animation.elem, animation.opts.queue ).stop =
					result.stop.bind( result );
			}
			return result;
		}
	}

	jQuery.map( props, createTween, animation );

	if ( isFunction( animation.opts.start ) ) {
		animation.opts.start.call( elem, animation );
	}

	// Attach callbacks from options
	animation
		.progress( animation.opts.progress )
		.done( animation.opts.done, animation.opts.complete )
		.fail( animation.opts.fail )
		.always( animation.opts.always );

	jQuery.fx.timer(
		jQuery.extend( tick, {
			elem: elem,
			anim: animation,
			queue: animation.opts.queue
		} )
	);

	return animation;
}

jQuery.Animation = jQuery.extend( Animation, {

	tweeners: {
		"*": [ function( prop, value ) {
			var tween = this.createTween( prop, value );
			adjustCSS( tween.elem, prop, rcssNum.exec( value ), tween );
			return tween;
		} ]
	},

	tweener: function( props, callback ) {
		if ( isFunction( props ) ) {
			callback = props;
			props = [ "*" ];
		} else {
			props = props.match( rnothtmlwhite );
		}

		var prop,
			index = 0,
			length = props.length;

		for ( ; index < length; index++ ) {
			prop = props[ index ];
			Animation.tweeners[ prop ] = Animation.tweeners[ prop ] || [];
			Animation.tweeners[ prop ].unshift( callback );
		}
	},

	prefilters: [ defaultPrefilter ],

	prefilter: function( callback, prepend ) {
		if ( prepend ) {
			Animation.prefilters.unshift( callback );
		} else {
			Animation.prefilters.push( callback );
		}
	}
} );

jQuery.speed = function( speed, easing, fn ) {
	var opt = speed && typeof speed === "object" ? jQuery.extend( {}, speed ) : {
		complete: fn || !fn && easing ||
			isFunction( speed ) && speed,
		duration: speed,
		easing: fn && easing || easing && !isFunction( easing ) && easing
	};

	// Go to the end state if fx are off
	if ( jQuery.fx.off ) {
		opt.duration = 0;

	} else {
		if ( typeof opt.duration !== "number" ) {
			if ( opt.duration in jQuery.fx.speeds ) {
				opt.duration = jQuery.fx.speeds[ opt.duration ];

			} else {
				opt.duration = jQuery.fx.speeds._default;
			}
		}
	}

	// Normalize opt.queue - true/undefined/null -> "fx"
	if ( opt.queue == null || opt.queue === true ) {
		opt.queue = "fx";
	}

	// Queueing
	opt.old = opt.complete;

	opt.complete = function() {
		if ( isFunction( opt.old ) ) {
			opt.old.call( this );
		}

		if ( opt.queue ) {
			jQuery.dequeue( this, opt.queue );
		}
	};

	return opt;
};

jQuery.fn.extend( {
	fadeTo: function( speed, to, easing, callback ) {

		// Show any hidden elements after setting opacity to 0
		return this.filter( isHiddenWithinTree ).css( "opacity", 0 ).show()

			// Animate to the value specified
			.end().animate( { opacity: to }, speed, easing, callback );
	},
	animate: function( prop, speed, easing, callback ) {
		var empty = jQuery.isEmptyObject( prop ),
			optall = jQuery.speed( speed, easing, callback ),
			doAnimation = function() {

				// Operate on a copy of prop so per-property easing won't be lost
				var anim = Animation( this, jQuery.extend( {}, prop ), optall );

				// Empty animations, or finishing resolves immediately
				if ( empty || dataPriv.get( this, "finish" ) ) {
					anim.stop( true );
				}
			};

		doAnimation.finish = doAnimation;

		return empty || optall.queue === false ?
			this.each( doAnimation ) :
			this.queue( optall.queue, doAnimation );
	},
	stop: function( type, clearQueue, gotoEnd ) {
		var stopQueue = function( hooks ) {
			var stop = hooks.stop;
			delete hooks.stop;
			stop( gotoEnd );
		};

		if ( typeof type !== "string" ) {
			gotoEnd = clearQueue;
			clearQueue = type;
			type = undefined;
		}
		if ( clearQueue ) {
			this.queue( type || "fx", [] );
		}

		return this.each( function() {
			var dequeue = true,
				index = type != null && type + "queueHooks",
				timers = jQuery.timers,
				data = dataPriv.get( this );

			if ( index ) {
				if ( data[ index ] && data[ index ].stop ) {
					stopQueue( data[ index ] );
				}
			} else {
				for ( index in data ) {
					if ( data[ index ] && data[ index ].stop && rrun.test( index ) ) {
						stopQueue( data[ index ] );
					}
				}
			}

			for ( index = timers.length; index--; ) {
				if ( timers[ index ].elem === this &&
					( type == null || timers[ index ].queue === type ) ) {

					timers[ index ].anim.stop( gotoEnd );
					dequeue = false;
					timers.splice( index, 1 );
				}
			}

			// Start the next in the queue if the last step wasn't forced.
			// Timers currently will call their complete callbacks, which
			// will dequeue but only if they were gotoEnd.
			if ( dequeue || !gotoEnd ) {
				jQuery.dequeue( this, type );
			}
		} );
	},
	finish: function( type ) {
		if ( type !== false ) {
			type = type || "fx";
		}
		return this.each( function() {
			var index,
				data = dataPriv.get( this ),
				queue = data[ type + "queue" ],
				hooks = data[ type + "queueHooks" ],
				timers = jQuery.timers,
				length = queue ? queue.length : 0;

			// Enable finishing flag on private data
			data.finish = true;

			// Empty the queue first
			jQuery.queue( this, type, [] );

			if ( hooks && hooks.stop ) {
				hooks.stop.call( this, true );
			}

			// Look for any active animations, and finish them
			for ( index = timers.length; index--; ) {
				if ( timers[ index ].elem === this && timers[ index ].queue === type ) {
					timers[ index ].anim.stop( true );
					timers.splice( index, 1 );
				}
			}

			// Look for any animations in the old queue and finish them
			for ( index = 0; index < length; index++ ) {
				if ( queue[ index ] && queue[ index ].finish ) {
					queue[ index ].finish.call( this );
				}
			}

			// Turn off finishing flag
			delete data.finish;
		} );
	}
} );

jQuery.each( [ "toggle", "show", "hide" ], function( _i, name ) {
	var cssFn = jQuery.fn[ name ];
	jQuery.fn[ name ] = function( speed, easing, callback ) {
		return speed == null || typeof speed === "boolean" ?
			cssFn.apply( this, arguments ) :
			this.animate( genFx( name, true ), speed, easing, callback );
	};
} );

// Generate shortcuts for custom animations
jQuery.each( {
	slideDown: genFx( "show" ),
	slideUp: genFx( "hide" ),
	slideToggle: genFx( "toggle" ),
	fadeIn: { opacity: "show" },
	fadeOut: { opacity: "hide" },
	fadeToggle: { opacity: "toggle" }
}, function( name, props ) {
	jQuery.fn[ name ] = function( speed, easing, callback ) {
		return this.animate( props, speed, easing, callback );
	};
} );

jQuery.timers = [];
jQuery.fx.tick = function() {
	var timer,
		i = 0,
		timers = jQuery.timers;

	fxNow = Date.now();

	for ( ; i < timers.length; i++ ) {
		timer = timers[ i ];

		// Run the timer and safely remove it when done (allowing for external removal)
		if ( !timer() && timers[ i ] === timer ) {
			timers.splice( i--, 1 );
		}
	}

	if ( !timers.length ) {
		jQuery.fx.stop();
	}
	fxNow = undefined;
};

jQuery.fx.timer = function( timer ) {
	jQuery.timers.push( timer );
	jQuery.fx.start();
};

jQuery.fx.interval = 13;
jQuery.fx.start = function() {
	if ( inProgress ) {
		return;
	}

	inProgress = true;
	schedule();
};

jQuery.fx.stop = function() {
	inProgress = null;
};

jQuery.fx.speeds = {
	slow: 600,
	fast: 200,

	// Default speed
	_default: 400
};


// Based off of the plugin by Clint Helfers, with permission.
// https://web.archive.org/web/20100324014747/http://blindsignals.com/index.php/2009/07/jquery-delay/
jQuery.fn.delay = function( time, type ) {
	time = jQuery.fx ? jQuery.fx.speeds[ time ] || time : time;
	type = type || "fx";

	return this.queue( type, function( next, hooks ) {
		var timeout = window.setTimeout( next, time );
		hooks.stop = function() {
			window.clearTimeout( timeout );
		};
	} );
};


( function() {
	var input = document.createElement( "input" ),
		select = document.createElement( "select" ),
		opt = select.appendChild( document.createElement( "option" ) );

	input.type = "checkbox";

	// Support: Android <=4.3 only
	// Default value for a checkbox should be "on"
	support.checkOn = input.value !== "";

	// Support: IE <=11 only
	// Must access selectedIndex to make default options select
	support.optSelected = opt.selected;

	// Support: IE <=11 only
	// An input loses its value after becoming a radio
	input = document.createElement( "input" );
	input.value = "t";
	input.type = "radio";
	support.radioValue = input.value === "t";
} )();


var boolHook,
	attrHandle = jQuery.expr.attrHandle;

jQuery.fn.extend( {
	attr: function( name, value ) {
		return access( this, jQuery.attr, name, value, arguments.length > 1 );
	},

	removeAttr: function( name ) {
		return this.each( function() {
			jQuery.removeAttr( this, name );
		} );
	}
} );

jQuery.extend( {
	attr: function( elem, name, value ) {
		var ret, hooks,
			nType = elem.nodeType;

		// Don't get/set attributes on text, comment and attribute nodes
		if ( nType === 3 || nType === 8 || nType === 2 ) {
			return;
		}

		// Fallback to prop when attributes are not supported
		if ( typeof elem.getAttribute === "undefined" ) {
			return jQuery.prop( elem, name, value );
		}

		// Attribute hooks are determined by the lowercase version
		// Grab necessary hook if one is defined
		if ( nType !== 1 || !jQuery.isXMLDoc( elem ) ) {
			hooks = jQuery.attrHooks[ name.toLowerCase() ] ||
				( jQuery.expr.match.bool.test( name ) ? boolHook : undefined );
		}

		if ( value !== undefined ) {
			if ( value === null ) {
				jQuery.removeAttr( elem, name );
				return;
			}

			if ( hooks && "set" in hooks &&
				( ret = hooks.set( elem, value, name ) ) !== undefined ) {
				return ret;
			}

			elem.setAttribute( name, value + "" );
			return value;
		}

		if ( hooks && "get" in hooks && ( ret = hooks.get( elem, name ) ) !== null ) {
			return ret;
		}

		ret = jQuery.find.attr( elem, name );

		// Non-existent attributes return null, we normalize to undefined
		return ret == null ? undefined : ret;
	},

	attrHooks: {
		type: {
			set: function( elem, value ) {
				if ( !support.radioValue && value === "radio" &&
					nodeName( elem, "input" ) ) {
					var val = elem.value;
					elem.setAttribute( "type", value );
					if ( val ) {
						elem.value = val;
					}
					return value;
				}
			}
		}
	},

	removeAttr: function( elem, value ) {
		var name,
			i = 0,

			// Attribute names can contain non-HTML whitespace characters
			// https://html.spec.whatwg.org/multipage/syntax.html#attributes-2
			attrNames = value && value.match( rnothtmlwhite );

		if ( attrNames && elem.nodeType === 1 ) {
			while ( ( name = attrNames[ i++ ] ) ) {
				elem.removeAttribute( name );
			}
		}
	}
} );

// Hooks for boolean attributes
boolHook = {
	set: function( elem, value, name ) {
		if ( value === false ) {

			// Remove boolean attributes when set to false
			jQuery.removeAttr( elem, name );
		} else {
			elem.setAttribute( name, name );
		}
		return name;
	}
};

jQuery.each( jQuery.expr.match.bool.source.match( /\w+/g ), function( _i, name ) {
	var getter = attrHandle[ name ] || jQuery.find.attr;

	attrHandle[ name ] = function( elem, name, isXML ) {
		var ret, handle,
			lowercaseName = name.toLowerCase();

		if ( !isXML ) {

			// Avoid an infinite loop by temporarily removing this function from the getter
			handle = attrHandle[ lowercaseName ];
			attrHandle[ lowercaseName ] = ret;
			ret = getter( elem, name, isXML ) != null ?
				lowercaseName :
				null;
			attrHandle[ lowercaseName ] = handle;
		}
		return ret;
	};
} );




var rfocusable = /^(?:input|select|textarea|button)$/i,
	rclickable = /^(?:a|area)$/i;

jQuery.fn.extend( {
	prop: function( name, value ) {
		return access( this, jQuery.prop, name, value, arguments.length > 1 );
	},

	removeProp: function( name ) {
		return this.each( function() {
			delete this[ jQuery.propFix[ name ] || name ];
		} );
	}
} );

jQuery.extend( {
	prop: function( elem, name, value ) {
		var ret, hooks,
			nType = elem.nodeType;

		// Don't get/set properties on text, comment and attribute nodes
		if ( nType === 3 || nType === 8 || nType === 2 ) {
			return;
		}

		if ( nType !== 1 || !jQuery.isXMLDoc( elem ) ) {

			// Fix name and attach hooks
			name = jQuery.propFix[ name ] || name;
			hooks = jQuery.propHooks[ name ];
		}

		if ( value !== undefined ) {
			if ( hooks && "set" in hooks &&
				( ret = hooks.set( elem, value, name ) ) !== undefined ) {
				return ret;
			}

			return ( elem[ name ] = value );
		}

		if ( hooks && "get" in hooks && ( ret = hooks.get( elem, name ) ) !== null ) {
			return ret;
		}

		return elem[ name ];
	},

	propHooks: {
		tabIndex: {
			get: function( elem ) {

				// Support: IE <=9 - 11 only
				// elem.tabIndex doesn't always return the
				// correct value when it hasn't been explicitly set
				// https://web.archive.org/web/20141116233347/http://fluidproject.org/blog/2008/01/09/getting-setting-and-removing-tabindex-values-with-javascript/
				// Use proper attribute retrieval(#12072)
				var tabindex = jQuery.find.attr( elem, "tabindex" );

				if ( tabindex ) {
					return parseInt( tabindex, 10 );
				}

				if (
					rfocusable.test( elem.nodeName ) ||
					rclickable.test( elem.nodeName ) &&
					elem.href
				) {
					return 0;
				}

				return -1;
			}
		}
	},

	propFix: {
		"for": "htmlFor",
		"class": "className"
	}
} );

// Support: IE <=11 only
// Accessing the selectedIndex property
// forces the browser to respect setting selected
// on the option
// The getter ensures a default option is selected
// when in an optgroup
// eslint rule "no-unused-expressions" is disabled for this code
// since it considers such accessions noop
if ( !support.optSelected ) {
	jQuery.propHooks.selected = {
		get: function( elem ) {

			/* eslint no-unused-expressions: "off" */

			var parent = elem.parentNode;
			if ( parent && parent.parentNode ) {
				parent.parentNode.selectedIndex;
			}
			return null;
		},
		set: function( elem ) {

			/* eslint no-unused-expressions: "off" */

			var parent = elem.parentNode;
			if ( parent ) {
				parent.selectedIndex;

				if ( parent.parentNode ) {
					parent.parentNode.selectedIndex;
				}
			}
		}
	};
}

jQuery.each( [
	"tabIndex",
	"readOnly",
	"maxLength",
	"cellSpacing",
	"cellPadding",
	"rowSpan",
	"colSpan",
	"useMap",
	"frameBorder",
	"contentEditable"
], function() {
	jQuery.propFix[ this.toLowerCase() ] = this;
} );




	// Strip and collapse whitespace according to HTML spec
	// https://infra.spec.whatwg.org/#strip-and-collapse-ascii-whitespace
	function stripAndCollapse( value ) {
		var tokens = value.match( rnothtmlwhite ) || [];
		return tokens.join( " " );
	}


function getClass( elem ) {
	return elem.getAttribute && elem.getAttribute( "class" ) || "";
}

function classesToArray( value ) {
	if ( Array.isArray( value ) ) {
		return value;
	}
	if ( typeof value === "string" ) {
		return value.match( rnothtmlwhite ) || [];
	}
	return [];
}

jQuery.fn.extend( {
	addClass: function( value ) {
		var classes, elem, cur, curValue, clazz, j, finalValue,
			i = 0;

		if ( isFunction( value ) ) {
			return this.each( function( j ) {
				jQuery( this ).addClass( value.call( this, j, getClass( this ) ) );
			} );
		}

		classes = classesToArray( value );

		if ( classes.length ) {
			while ( ( elem = this[ i++ ] ) ) {
				curValue = getClass( elem );
				cur = elem.nodeType === 1 && ( " " + stripAndCollapse( curValue ) + " " );

				if ( cur ) {
					j = 0;
					while ( ( clazz = classes[ j++ ] ) ) {
						if ( cur.indexOf( " " + clazz + " " ) < 0 ) {
							cur += clazz + " ";
						}
					}

					// Only assign if different to avoid unneeded rendering.
					finalValue = stripAndCollapse( cur );
					if ( curValue !== finalValue ) {
						elem.setAttribute( "class", finalValue );
					}
				}
			}
		}

		return this;
	},

	removeClass: function( value ) {
		var classes, elem, cur, curValue, clazz, j, finalValue,
			i = 0;

		if ( isFunction( value ) ) {
			return this.each( function( j ) {
				jQuery( this ).removeClass( value.call( this, j, getClass( this ) ) );
			} );
		}

		if ( !arguments.length ) {
			return this.attr( "class", "" );
		}

		classes = classesToArray( value );

		if ( classes.length ) {
			while ( ( elem = this[ i++ ] ) ) {
				curValue = getClass( elem );

				// This expression is here for better compressibility (see addClass)
				cur = elem.nodeType === 1 && ( " " + stripAndCollapse( curValue ) + " " );

				if ( cur ) {
					j = 0;
					while ( ( clazz = classes[ j++ ] ) ) {

						// Remove *all* instances
						while ( cur.indexOf( " " + clazz + " " ) > -1 ) {
							cur = cur.replace( " " + clazz + " ", " " );
						}
					}

					// Only assign if different to avoid unneeded rendering.
					finalValue = stripAndCollapse( cur );
					if ( curValue !== finalValue ) {
						elem.setAttribute( "class", finalValue );
					}
				}
			}
		}

		return this;
	},

	toggleClass: function( value, stateVal ) {
		var type = typeof value,
			isValidValue = type === "string" || Array.isArray( value );

		if ( typeof stateVal === "boolean" && isValidValue ) {
			return stateVal ? this.addClass( value ) : this.removeClass( value );
		}

		if ( isFunction( value ) ) {
			return this.each( function( i ) {
				jQuery( this ).toggleClass(
					value.call( this, i, getClass( this ), stateVal ),
					stateVal
				);
			} );
		}

		return this.each( function() {
			var className, i, self, classNames;

			if ( isValidValue ) {

				// Toggle individual class names
				i = 0;
				self = jQuery( this );
				classNames = classesToArray( value );

				while ( ( className = classNames[ i++ ] ) ) {

					// Check each className given, space separated list
					if ( self.hasClass( className ) ) {
						self.removeClass( className );
					} else {
						self.addClass( className );
					}
				}

			// Toggle whole class name
			} else if ( value === undefined || type === "boolean" ) {
				className = getClass( this );
				if ( className ) {

					// Store className if set
					dataPriv.set( this, "__className__", className );
				}

				// If the element has a class name or if we're passed `false`,
				// then remove the whole classname (if there was one, the above saved it).
				// Otherwise bring back whatever was previously saved (if anything),
				// falling back to the empty string if nothing was stored.
				if ( this.setAttribute ) {
					this.setAttribute( "class",
						className || value === false ?
							"" :
							dataPriv.get( this, "__className__" ) || ""
					);
				}
			}
		} );
	},

	hasClass: function( selector ) {
		var className, elem,
			i = 0;

		className = " " + selector + " ";
		while ( ( elem = this[ i++ ] ) ) {
			if ( elem.nodeType === 1 &&
				( " " + stripAndCollapse( getClass( elem ) ) + " " ).indexOf( className ) > -1 ) {
				return true;
			}
		}

		return false;
	}
} );




var rreturn = /\r/g;

jQuery.fn.extend( {
	val: function( value ) {
		var hooks, ret, valueIsFunction,
			elem = this[ 0 ];

		if ( !arguments.length ) {
			if ( elem ) {
				hooks = jQuery.valHooks[ elem.type ] ||
					jQuery.valHooks[ elem.nodeName.toLowerCase() ];

				if ( hooks &&
					"get" in hooks &&
					( ret = hooks.get( elem, "value" ) ) !== undefined
				) {
					return ret;
				}

				ret = elem.value;

				// Handle most common string cases
				if ( typeof ret === "string" ) {
					return ret.replace( rreturn, "" );
				}

				// Handle cases where value is null/undef or number
				return ret == null ? "" : ret;
			}

			return;
		}

		valueIsFunction = isFunction( value );

		return this.each( function( i ) {
			var val;

			if ( this.nodeType !== 1 ) {
				return;
			}

			if ( valueIsFunction ) {
				val = value.call( this, i, jQuery( this ).val() );
			} else {
				val = value;
			}

			// Treat null/undefined as ""; convert numbers to string
			if ( val == null ) {
				val = "";

			} else if ( typeof val === "number" ) {
				val += "";

			} else if ( Array.isArray( val ) ) {
				val = jQuery.map( val, function( value ) {
					return value == null ? "" : value + "";
				} );
			}

			hooks = jQuery.valHooks[ this.type ] || jQuery.valHooks[ this.nodeName.toLowerCase() ];

			// If set returns undefined, fall back to normal setting
			if ( !hooks || !( "set" in hooks ) || hooks.set( this, val, "value" ) === undefined ) {
				this.value = val;
			}
		} );
	}
} );

jQuery.extend( {
	valHooks: {
		option: {
			get: function( elem ) {

				var val = jQuery.find.attr( elem, "value" );
				return val != null ?
					val :

					// Support: IE <=10 - 11 only
					// option.text throws exceptions (#14686, #14858)
					// Strip and collapse whitespace
					// https://html.spec.whatwg.org/#strip-and-collapse-whitespace
					stripAndCollapse( jQuery.text( elem ) );
			}
		},
		select: {
			get: function( elem ) {
				var value, option, i,
					options = elem.options,
					index = elem.selectedIndex,
					one = elem.type === "select-one",
					values = one ? null : [],
					max = one ? index + 1 : options.length;

				if ( index < 0 ) {
					i = max;

				} else {
					i = one ? index : 0;
				}

				// Loop through all the selected options
				for ( ; i < max; i++ ) {
					option = options[ i ];

					// Support: IE <=9 only
					// IE8-9 doesn't update selected after form reset (#2551)
					if ( ( option.selected || i === index ) &&

							// Don't return options that are disabled or in a disabled optgroup
							!option.disabled &&
							( !option.parentNode.disabled ||
								!nodeName( option.parentNode, "optgroup" ) ) ) {

						// Get the specific value for the option
						value = jQuery( option ).val();

						// We don't need an array for one selects
						if ( one ) {
							return value;
						}

						// Multi-Selects return an array
						values.push( value );
					}
				}

				return values;
			},

			set: function( elem, value ) {
				var optionSet, option,
					options = elem.options,
					values = jQuery.makeArray( value ),
					i = options.length;

				while ( i-- ) {
					option = options[ i ];

					/* eslint-disable no-cond-assign */

					if ( option.selected =
						jQuery.inArray( jQuery.valHooks.option.get( option ), values ) > -1
					) {
						optionSet = true;
					}

					/* eslint-enable no-cond-assign */
				}

				// Force browsers to behave consistently when non-matching value is set
				if ( !optionSet ) {
					elem.selectedIndex = -1;
				}
				return values;
			}
		}
	}
} );

// Radios and checkboxes getter/setter
jQuery.each( [ "radio", "checkbox" ], function() {
	jQuery.valHooks[ this ] = {
		set: function( elem, value ) {
			if ( Array.isArray( value ) ) {
				return ( elem.checked = jQuery.inArray( jQuery( elem ).val(), value ) > -1 );
			}
		}
	};
	if ( !support.checkOn ) {
		jQuery.valHooks[ this ].get = function( elem ) {
			return elem.getAttribute( "value" ) === null ? "on" : elem.value;
		};
	}
} );




// Return jQuery for attributes-only inclusion


support.focusin = "onfocusin" in window;


var rfocusMorph = /^(?:focusinfocus|focusoutblur)$/,
	stopPropagationCallback = function( e ) {
		e.stopPropagation();
	};

jQuery.extend( jQuery.event, {

	trigger: function( event, data, elem, onlyHandlers ) {

		var i, cur, tmp, bubbleType, ontype, handle, special, lastElement,
			eventPath = [ elem || document ],
			type = hasOwn.call( event, "type" ) ? event.type : event,
			namespaces = hasOwn.call( event, "namespace" ) ? event.namespace.split( "." ) : [];

		cur = lastElement = tmp = elem = elem || document;

		// Don't do events on text and comment nodes
		if ( elem.nodeType === 3 || elem.nodeType === 8 ) {
			return;
		}

		// focus/blur morphs to focusin/out; ensure we're not firing them right now
		if ( rfocusMorph.test( type + jQuery.event.triggered ) ) {
			return;
		}

		if ( type.indexOf( "." ) > -1 ) {

			// Namespaced trigger; create a regexp to match event type in handle()
			namespaces = type.split( "." );
			type = namespaces.shift();
			namespaces.sort();
		}
		ontype = type.indexOf( ":" ) < 0 && "on" + type;

		// Caller can pass in a jQuery.Event object, Object, or just an event type string
		event = event[ jQuery.expando ] ?
			event :
			new jQuery.Event( type, typeof event === "object" && event );

		// Trigger bitmask: & 1 for native handlers; & 2 for jQuery (always true)
		event.isTrigger = onlyHandlers ? 2 : 3;
		event.namespace = namespaces.join( "." );
		event.rnamespace = event.namespace ?
			new RegExp( "(^|\\.)" + namespaces.join( "\\.(?:.*\\.|)" ) + "(\\.|$)" ) :
			null;

		// Clean up the event in case it is being reused
		event.result = undefined;
		if ( !event.target ) {
			event.target = elem;
		}

		// Clone any incoming data and prepend the event, creating the handler arg list
		data = data == null ?
			[ event ] :
			jQuery.makeArray( data, [ event ] );

		// Allow special events to draw outside the lines
		special = jQuery.event.special[ type ] || {};
		if ( !onlyHandlers && special.trigger && special.trigger.apply( elem, data ) === false ) {
			return;
		}

		// Determine event propagation path in advance, per W3C events spec (#9951)
		// Bubble up to document, then to window; watch for a global ownerDocument var (#9724)
		if ( !onlyHandlers && !special.noBubble && !isWindow( elem ) ) {

			bubbleType = special.delegateType || type;
			if ( !rfocusMorph.test( bubbleType + type ) ) {
				cur = cur.parentNode;
			}
			for ( ; cur; cur = cur.parentNode ) {
				eventPath.push( cur );
				tmp = cur;
			}

			// Only add window if we got to document (e.g., not plain obj or detached DOM)
			if ( tmp === ( elem.ownerDocument || document ) ) {
				eventPath.push( tmp.defaultView || tmp.parentWindow || window );
			}
		}

		// Fire handlers on the event path
		i = 0;
		while ( ( cur = eventPath[ i++ ] ) && !event.isPropagationStopped() ) {
			lastElement = cur;
			event.type = i > 1 ?
				bubbleType :
				special.bindType || type;

			// jQuery handler
			handle = ( dataPriv.get( cur, "events" ) || Object.create( null ) )[ event.type ] &&
				dataPriv.get( cur, "handle" );
			if ( handle ) {
				handle.apply( cur, data );
			}

			// Native handler
			handle = ontype && cur[ ontype ];
			if ( handle && handle.apply && acceptData( cur ) ) {
				event.result = handle.apply( cur, data );
				if ( event.result === false ) {
					event.preventDefault();
				}
			}
		}
		event.type = type;

		// If nobody prevented the default action, do it now
		if ( !onlyHandlers && !event.isDefaultPrevented() ) {

			if ( ( !special._default ||
				special._default.apply( eventPath.pop(), data ) === false ) &&
				acceptData( elem ) ) {

				// Call a native DOM method on the target with the same name as the event.
				// Don't do default actions on window, that's where global variables be (#6170)
				if ( ontype && isFunction( elem[ type ] ) && !isWindow( elem ) ) {

					// Don't re-trigger an onFOO event when we call its FOO() method
					tmp = elem[ ontype ];

					if ( tmp ) {
						elem[ ontype ] = null;
					}

					// Prevent re-triggering of the same event, since we already bubbled it above
					jQuery.event.triggered = type;

					if ( event.isPropagationStopped() ) {
						lastElement.addEventListener( type, stopPropagationCallback );
					}

					elem[ type ]();

					if ( event.isPropagationStopped() ) {
						lastElement.removeEventListener( type, stopPropagationCallback );
					}

					jQuery.event.triggered = undefined;

					if ( tmp ) {
						elem[ ontype ] = tmp;
					}
				}
			}
		}

		return event.result;
	},

	// Piggyback on a donor event to simulate a different one
	// Used only for `focus(in | out)` events
	simulate: function( type, elem, event ) {
		var e = jQuery.extend(
			new jQuery.Event(),
			event,
			{
				type: type,
				isSimulated: true
			}
		);

		jQuery.event.trigger( e, null, elem );
	}

} );

jQuery.fn.extend( {

	trigger: function( type, data ) {
		return this.each( function() {
			jQuery.event.trigger( type, data, this );
		} );
	},
	triggerHandler: function( type, data ) {
		var elem = this[ 0 ];
		if ( elem ) {
			return jQuery.event.trigger( type, data, elem, true );
		}
	}
} );


// Support: Firefox <=44
// Firefox doesn't have focus(in | out) events
// Related ticket - https://bugzilla.mozilla.org/show_bug.cgi?id=687787
//
// Support: Chrome <=48 - 49, Safari <=9.0 - 9.1
// focus(in | out) events fire after focus & blur events,
// which is spec violation - http://www.w3.org/TR/DOM-Level-3-Events/#events-focusevent-event-order
// Related ticket - https://bugs.chromium.org/p/chromium/issues/detail?id=449857
if ( !support.focusin ) {
	jQuery.each( { focus: "focusin", blur: "focusout" }, function( orig, fix ) {

		// Attach a single capturing handler on the document while someone wants focusin/focusout
		var handler = function( event ) {
			jQuery.event.simulate( fix, event.target, jQuery.event.fix( event ) );
		};

		jQuery.event.special[ fix ] = {
			setup: function() {

				// Handle: regular nodes (via `this.ownerDocument`), window
				// (via `this.document`) & document (via `this`).
				var doc = this.ownerDocument || this.document || this,
					attaches = dataPriv.access( doc, fix );

				if ( !attaches ) {
					doc.addEventListener( orig, handler, true );
				}
				dataPriv.access( doc, fix, ( attaches || 0 ) + 1 );
			},
			teardown: function() {
				var doc = this.ownerDocument || this.document || this,
					attaches = dataPriv.access( doc, fix ) - 1;

				if ( !attaches ) {
					doc.removeEventListener( orig, handler, true );
					dataPriv.remove( doc, fix );

				} else {
					dataPriv.access( doc, fix, attaches );
				}
			}
		};
	} );
}
var location = window.location;

var nonce = { guid: Date.now() };

var rquery = ( /\?/ );



// Cross-browser xml parsing
jQuery.parseXML = function( data ) {
	var xml, parserErrorElem;
	if ( !data || typeof data !== "string" ) {
		return null;
	}

	// Support: IE 9 - 11 only
	// IE throws on parseFromString with invalid input.
	try {
		xml = ( new window.DOMParser() ).parseFromString( data, "text/xml" );
	} catch ( e ) {}

	parserErrorElem = xml && xml.getElementsByTagName( "parsererror" )[ 0 ];
	if ( !xml || parserErrorElem ) {
		jQuery.error( "Invalid XML: " + (
			parserErrorElem ?
				jQuery.map( parserErrorElem.childNodes, function( el ) {
					return el.textContent;
				} ).join( "\n" ) :
				data
		) );
	}
	return xml;
};


var
	rbracket = /\[\]$/,
	rCRLF = /\r?\n/g,
	rsubmitterTypes = /^(?:submit|button|image|reset|file)$/i,
	rsubmittable = /^(?:input|select|textarea|keygen)/i;

function buildParams( prefix, obj, traditional, add ) {
	var name;

	if ( Array.isArray( obj ) ) {

		// Serialize array item.
		jQuery.each( obj, function( i, v ) {
			if ( traditional || rbracket.test( prefix ) ) {

				// Treat each array item as a scalar.
				add( prefix, v );

			} else {

				// Item is non-scalar (array or object), encode its numeric index.
				buildParams(
					prefix + "[" + ( typeof v === "object" && v != null ? i : "" ) + "]",
					v,
					traditional,
					add
				);
			}
		} );

	} else if ( !traditional && toType( obj ) === "object" ) {

		// Serialize object item.
		for ( name in obj ) {
			buildParams( prefix + "[" + name + "]", obj[ name ], traditional, add );
		}

	} else {

		// Serialize scalar item.
		add( prefix, obj );
	}
}

// Serialize an array of form elements or a set of
// key/values into a query string
jQuery.param = function( a, traditional ) {
	var prefix,
		s = [],
		add = function( key, valueOrFunction ) {

			// If value is a function, invoke it and use its return value
			var value = isFunction( valueOrFunction ) ?
				valueOrFunction() :
				valueOrFunction;

			s[ s.length ] = encodeURIComponent( key ) + "=" +
				encodeURIComponent( value == null ? "" : value );
		};

	if ( a == null ) {
		return "";
	}

	// If an array was passed in, assume that it is an array of form elements.
	if ( Array.isArray( a ) || ( a.jquery && !jQuery.isPlainObject( a ) ) ) {

		// Serialize the form elements
		jQuery.each( a, function() {
			add( this.name, this.value );
		} );

	} else {

		// If traditional, encode the "old" way (the way 1.3.2 or older
		// did it), otherwise encode params recursively.
		for ( prefix in a ) {
			buildParams( prefix, a[ prefix ], traditional, add );
		}
	}

	// Return the resulting serialization
	return s.join( "&" );
};

jQuery.fn.extend( {
	serialize: function() {
		return jQuery.param( this.serializeArray() );
	},
	serializeArray: function() {
		return this.map( function() {

			// Can add propHook for "elements" to filter or add form elements
			var elements = jQuery.prop( this, "elements" );
			return elements ? jQuery.makeArray( elements ) : this;
		} ).filter( function() {
			var type = this.type;

			// Use .is( ":disabled" ) so that fieldset[disabled] works
			return this.name && !jQuery( this ).is( ":disabled" ) &&
				rsubmittable.test( this.nodeName ) && !rsubmitterTypes.test( type ) &&
				( this.checked || !rcheckableType.test( type ) );
		} ).map( function( _i, elem ) {
			var val = jQuery( this ).val();

			if ( val == null ) {
				return null;
			}

			if ( Array.isArray( val ) ) {
				return jQuery.map( val, function( val ) {
					return { name: elem.name, value: val.replace( rCRLF, "\r\n" ) };
				} );
			}

			return { name: elem.name, value: val.replace( rCRLF, "\r\n" ) };
		} ).get();
	}
} );


var
	r20 = /%20/g,
	rhash = /#.*$/,
	rantiCache = /([?&])_=[^&]*/,
	rheaders = /^(.*?):[ \t]*([^\r\n]*)$/mg,

	// #7653, #8125, #8152: local protocol detection
	rlocalProtocol = /^(?:about|app|app-storage|.+-extension|file|res|widget):$/,
	rnoContent = /^(?:GET|HEAD)$/,
	rprotocol = /^\/\//,

	/* Prefilters
	 * 1) They are useful to introduce custom dataTypes (see ajax/jsonp.js for an example)
	 * 2) These are called:
	 *    - BEFORE asking for a transport
	 *    - AFTER param serialization (s.data is a string if s.processData is true)
	 * 3) key is the dataType
	 * 4) the catchall symbol "*" can be used
	 * 5) execution will start with transport dataType and THEN continue down to "*" if needed
	 */
	prefilters = {},

	/* Transports bindings
	 * 1) key is the dataType
	 * 2) the catchall symbol "*" can be used
	 * 3) selection will start with transport dataType and THEN go to "*" if needed
	 */
	transports = {},

	// Avoid comment-prolog char sequence (#10098); must appease lint and evade compression
	allTypes = "*/".concat( "*" ),

	// Anchor tag for parsing the document origin
	originAnchor = document.createElement( "a" );

originAnchor.href = location.href;

// Base "constructor" for jQuery.ajaxPrefilter and jQuery.ajaxTransport
function addToPrefiltersOrTransports( structure ) {

	// dataTypeExpression is optional and defaults to "*"
	return function( dataTypeExpression, func ) {

		if ( typeof dataTypeExpression !== "string" ) {
			func = dataTypeExpression;
			dataTypeExpression = "*";
		}

		var dataType,
			i = 0,
			dataTypes = dataTypeExpression.toLowerCase().match( rnothtmlwhite ) || [];

		if ( isFunction( func ) ) {

			// For each dataType in the dataTypeExpression
			while ( ( dataType = dataTypes[ i++ ] ) ) {

				// Prepend if requested
				if ( dataType[ 0 ] === "+" ) {
					dataType = dataType.slice( 1 ) || "*";
					( structure[ dataType ] = structure[ dataType ] || [] ).unshift( func );

				// Otherwise append
				} else {
					( structure[ dataType ] = structure[ dataType ] || [] ).push( func );
				}
			}
		}
	};
}

// Base inspection function for prefilters and transports
function inspectPrefiltersOrTransports( structure, options, originalOptions, jqXHR ) {

	var inspected = {},
		seekingTransport = ( structure === transports );

	function inspect( dataType ) {
		var selected;
		inspected[ dataType ] = true;
		jQuery.each( structure[ dataType ] || [], function( _, prefilterOrFactory ) {
			var dataTypeOrTransport = prefilterOrFactory( options, originalOptions, jqXHR );
			if ( typeof dataTypeOrTransport === "string" &&
				!seekingTransport && !inspected[ dataTypeOrTransport ] ) {

				options.dataTypes.unshift( dataTypeOrTransport );
				inspect( dataTypeOrTransport );
				return false;
			} else if ( seekingTransport ) {
				return !( selected = dataTypeOrTransport );
			}
		} );
		return selected;
	}

	return inspect( options.dataTypes[ 0 ] ) || !inspected[ "*" ] && inspect( "*" );
}

// A special extend for ajax options
// that takes "flat" options (not to be deep extended)
// Fixes #9887
function ajaxExtend( target, src ) {
	var key, deep,
		flatOptions = jQuery.ajaxSettings.flatOptions || {};

	for ( key in src ) {
		if ( src[ key ] !== undefined ) {
			( flatOptions[ key ] ? target : ( deep || ( deep = {} ) ) )[ key ] = src[ key ];
		}
	}
	if ( deep ) {
		jQuery.extend( true, target, deep );
	}

	return target;
}

/* Handles responses to an ajax request:
 * - finds the right dataType (mediates between content-type and expected dataType)
 * - returns the corresponding response
 */
function ajaxHandleResponses( s, jqXHR, responses ) {

	var ct, type, finalDataType, firstDataType,
		contents = s.contents,
		dataTypes = s.dataTypes;

	// Remove auto dataType and get content-type in the process
	while ( dataTypes[ 0 ] === "*" ) {
		dataTypes.shift();
		if ( ct === undefined ) {
			ct = s.mimeType || jqXHR.getResponseHeader( "Content-Type" );
		}
	}

	// Check if we're dealing with a known content-type
	if ( ct ) {
		for ( type in contents ) {
			if ( contents[ type ] && contents[ type ].test( ct ) ) {
				dataTypes.unshift( type );
				break;
			}
		}
	}

	// Check to see if we have a response for the expected dataType
	if ( dataTypes[ 0 ] in responses ) {
		finalDataType = dataTypes[ 0 ];
	} else {

		// Try convertible dataTypes
		for ( type in responses ) {
			if ( !dataTypes[ 0 ] || s.converters[ type + " " + dataTypes[ 0 ] ] ) {
				finalDataType = type;
				break;
			}
			if ( !firstDataType ) {
				firstDataType = type;
			}
		}

		// Or just use first one
		finalDataType = finalDataType || firstDataType;
	}

	// If we found a dataType
	// We add the dataType to the list if needed
	// and return the corresponding response
	if ( finalDataType ) {
		if ( finalDataType !== dataTypes[ 0 ] ) {
			dataTypes.unshift( finalDataType );
		}
		return responses[ finalDataType ];
	}
}

/* Chain conversions given the request and the original response
 * Also sets the responseXXX fields on the jqXHR instance
 */
function ajaxConvert( s, response, jqXHR, isSuccess ) {
	var conv2, current, conv, tmp, prev,
		converters = {},

		// Work with a copy of dataTypes in case we need to modify it for conversion
		dataTypes = s.dataTypes.slice();

	// Create converters map with lowercased keys
	if ( dataTypes[ 1 ] ) {
		for ( conv in s.converters ) {
			converters[ conv.toLowerCase() ] = s.converters[ conv ];
		}
	}

	current = dataTypes.shift();

	// Convert to each sequential dataType
	while ( current ) {

		if ( s.responseFields[ current ] ) {
			jqXHR[ s.responseFields[ current ] ] = response;
		}

		// Apply the dataFilter if provided
		if ( !prev && isSuccess && s.dataFilter ) {
			response = s.dataFilter( response, s.dataType );
		}

		prev = current;
		current = dataTypes.shift();

		if ( current ) {

			// There's only work to do if current dataType is non-auto
			if ( current === "*" ) {

				current = prev;

			// Convert response if prev dataType is non-auto and differs from current
			} else if ( prev !== "*" && prev !== current ) {

				// Seek a direct converter
				conv = converters[ prev + " " + current ] || converters[ "* " + current ];

				// If none found, seek a pair
				if ( !conv ) {
					for ( conv2 in converters ) {

						// If conv2 outputs current
						tmp = conv2.split( " " );
						if ( tmp[ 1 ] === current ) {

							// If prev can be converted to accepted input
							conv = converters[ prev + " " + tmp[ 0 ] ] ||
								converters[ "* " + tmp[ 0 ] ];
							if ( conv ) {

								// Condense equivalence converters
								if ( conv === true ) {
									conv = converters[ conv2 ];

								// Otherwise, insert the intermediate dataType
								} else if ( converters[ conv2 ] !== true ) {
									current = tmp[ 0 ];
									dataTypes.unshift( tmp[ 1 ] );
								}
								break;
							}
						}
					}
				}

				// Apply converter (if not an equivalence)
				if ( conv !== true ) {

					// Unless errors are allowed to bubble, catch and return them
					if ( conv && s.throws ) {
						response = conv( response );
					} else {
						try {
							response = conv( response );
						} catch ( e ) {
							return {
								state: "parsererror",
								error: conv ? e : "No conversion from " + prev + " to " + current
							};
						}
					}
				}
			}
		}
	}

	return { state: "success", data: response };
}

jQuery.extend( {

	// Counter for holding the number of active queries
	active: 0,

	// Last-Modified header cache for next request
	lastModified: {},
	etag: {},

	ajaxSettings: {
		url: location.href,
		type: "GET",
		isLocal: rlocalProtocol.test( location.protocol ),
		global: true,
		processData: true,
		async: true,
		contentType: "application/x-www-form-urlencoded; charset=UTF-8",

		/*
		timeout: 0,
		data: null,
		dataType: null,
		username: null,
		password: null,
		cache: null,
		throws: false,
		traditional: false,
		headers: {},
		*/

		accepts: {
			"*": allTypes,
			text: "text/plain",
			html: "text/html",
			xml: "application/xml, text/xml",
			json: "application/json, text/javascript"
		},

		contents: {
			xml: /\bxml\b/,
			html: /\bhtml/,
			json: /\bjson\b/
		},

		responseFields: {
			xml: "responseXML",
			text: "responseText",
			json: "responseJSON"
		},

		// Data converters
		// Keys separate source (or catchall "*") and destination types with a single space
		converters: {

			// Convert anything to text
			"* text": String,

			// Text to html (true = no transformation)
			"text html": true,

			// Evaluate text as a json expression
			"text json": JSON.parse,

			// Parse text as xml
			"text xml": jQuery.parseXML
		},

		// For options that shouldn't be deep extended:
		// you can add your own custom options here if
		// and when you create one that shouldn't be
		// deep extended (see ajaxExtend)
		flatOptions: {
			url: true,
			context: true
		}
	},

	// Creates a full fledged settings object into target
	// with both ajaxSettings and settings fields.
	// If target is omitted, writes into ajaxSettings.
	ajaxSetup: function( target, settings ) {
		return settings ?

			// Building a settings object
			ajaxExtend( ajaxExtend( target, jQuery.ajaxSettings ), settings ) :

			// Extending ajaxSettings
			ajaxExtend( jQuery.ajaxSettings, target );
	},

	ajaxPrefilter: addToPrefiltersOrTransports( prefilters ),
	ajaxTransport: addToPrefiltersOrTransports( transports ),

	// Main method
	ajax: function( url, options ) {

		// If url is an object, simulate pre-1.5 signature
		if ( typeof url === "object" ) {
			options = url;
			url = undefined;
		}

		// Force options to be an object
		options = options || {};

		var transport,

			// URL without anti-cache param
			cacheURL,

			// Response headers
			responseHeadersString,
			responseHeaders,

			// timeout handle
			timeoutTimer,

			// Url cleanup var
			urlAnchor,

			// Request state (becomes false upon send and true upon completion)
			completed,

			// To know if global events are to be dispatched
			fireGlobals,

			// Loop variable
			i,

			// uncached part of the url
			uncached,

			// Create the final options object
			s = jQuery.ajaxSetup( {}, options ),

			// Callbacks context
			callbackContext = s.context || s,

			// Context for global events is callbackContext if it is a DOM node or jQuery collection
			globalEventContext = s.context &&
				( callbackContext.nodeType || callbackContext.jquery ) ?
				jQuery( callbackContext ) :
				jQuery.event,

			// Deferreds
			deferred = jQuery.Deferred(),
			completeDeferred = jQuery.Callbacks( "once memory" ),

			// Status-dependent callbacks
			statusCode = s.statusCode || {},

			// Headers (they are sent all at once)
			requestHeaders = {},
			requestHeadersNames = {},

			// Default abort message
			strAbort = "canceled",

			// Fake xhr
			jqXHR = {
				readyState: 0,

				// Builds headers hashtable if needed
				getResponseHeader: function( key ) {
					var match;
					if ( completed ) {
						if ( !responseHeaders ) {
							responseHeaders = {};
							while ( ( match = rheaders.exec( responseHeadersString ) ) ) {
								responseHeaders[ match[ 1 ].toLowerCase() + " " ] =
									( responseHeaders[ match[ 1 ].toLowerCase() + " " ] || [] )
										.concat( match[ 2 ] );
							}
						}
						match = responseHeaders[ key.toLowerCase() + " " ];
					}
					return match == null ? null : match.join( ", " );
				},

				// Raw string
				getAllResponseHeaders: function() {
					return completed ? responseHeadersString : null;
				},

				// Caches the header
				setRequestHeader: function( name, value ) {
					if ( completed == null ) {
						name = requestHeadersNames[ name.toLowerCase() ] =
							requestHeadersNames[ name.toLowerCase() ] || name;
						requestHeaders[ name ] = value;
					}
					return this;
				},

				// Overrides response content-type header
				overrideMimeType: function( type ) {
					if ( completed == null ) {
						s.mimeType = type;
					}
					return this;
				},

				// Status-dependent callbacks
				statusCode: function( map ) {
					var code;
					if ( map ) {
						if ( completed ) {

							// Execute the appropriate callbacks
							jqXHR.always( map[ jqXHR.status ] );
						} else {

							// Lazy-add the new callbacks in a way that preserves old ones
							for ( code in map ) {
								statusCode[ code ] = [ statusCode[ code ], map[ code ] ];
							}
						}
					}
					return this;
				},

				// Cancel the request
				abort: function( statusText ) {
					var finalText = statusText || strAbort;
					if ( transport ) {
						transport.abort( finalText );
					}
					done( 0, finalText );
					return this;
				}
			};

		// Attach deferreds
		deferred.promise( jqXHR );

		// Add protocol if not provided (prefilters might expect it)
		// Handle falsy url in the settings object (#10093: consistency with old signature)
		// We also use the url parameter if available
		s.url = ( ( url || s.url || location.href ) + "" )
			.replace( rprotocol, location.protocol + "//" );

		// Alias method option to type as per ticket #12004
		s.type = options.method || options.type || s.method || s.type;

		// Extract dataTypes list
		s.dataTypes = ( s.dataType || "*" ).toLowerCase().match( rnothtmlwhite ) || [ "" ];

		// A cross-domain request is in order when the origin doesn't match the current origin.
		if ( s.crossDomain == null ) {
			urlAnchor = document.createElement( "a" );

			// Support: IE <=8 - 11, Edge 12 - 15
			// IE throws exception on accessing the href property if url is malformed,
			// e.g. http://example.com:80x/
			try {
				urlAnchor.href = s.url;

				// Support: IE <=8 - 11 only
				// Anchor's host property isn't correctly set when s.url is relative
				urlAnchor.href = urlAnchor.href;
				s.crossDomain = originAnchor.protocol + "//" + originAnchor.host !==
					urlAnchor.protocol + "//" + urlAnchor.host;
			} catch ( e ) {

				// If there is an error parsing the URL, assume it is crossDomain,
				// it can be rejected by the transport if it is invalid
				s.crossDomain = true;
			}
		}

		// Convert data if not already a string
		if ( s.data && s.processData && typeof s.data !== "string" ) {
			s.data = jQuery.param( s.data, s.traditional );
		}

		// Apply prefilters
		inspectPrefiltersOrTransports( prefilters, s, options, jqXHR );

		// If request was aborted inside a prefilter, stop there
		if ( completed ) {
			return jqXHR;
		}

		// We can fire global events as of now if asked to
		// Don't fire events if jQuery.event is undefined in an AMD-usage scenario (#15118)
		fireGlobals = jQuery.event && s.global;

		// Watch for a new set of requests
		if ( fireGlobals && jQuery.active++ === 0 ) {
			jQuery.event.trigger( "ajaxStart" );
		}

		// Uppercase the type
		s.type = s.type.toUpperCase();

		// Determine if request has content
		s.hasContent = !rnoContent.test( s.type );

		// Save the URL in case we're toying with the If-Modified-Since
		// and/or If-None-Match header later on
		// Remove hash to simplify url manipulation
		cacheURL = s.url.replace( rhash, "" );

		// More options handling for requests with no content
		if ( !s.hasContent ) {

			// Remember the hash so we can put it back
			uncached = s.url.slice( cacheURL.length );

			// If data is available and should be processed, append data to url
			if ( s.data && ( s.processData || typeof s.data === "string" ) ) {
				cacheURL += ( rquery.test( cacheURL ) ? "&" : "?" ) + s.data;

				// #9682: remove data so that it's not used in an eventual retry
				delete s.data;
			}

			// Add or update anti-cache param if needed
			if ( s.cache === false ) {
				cacheURL = cacheURL.replace( rantiCache, "$1" );
				uncached = ( rquery.test( cacheURL ) ? "&" : "?" ) + "_=" + ( nonce.guid++ ) +
					uncached;
			}

			// Put hash and anti-cache on the URL that will be requested (gh-1732)
			s.url = cacheURL + uncached;

		// Change '%20' to '+' if this is encoded form body content (gh-2658)
		} else if ( s.data && s.processData &&
			( s.contentType || "" ).indexOf( "application/x-www-form-urlencoded" ) === 0 ) {
			s.data = s.data.replace( r20, "+" );
		}

		// Set the If-Modified-Since and/or If-None-Match header, if in ifModified mode.
		if ( s.ifModified ) {
			if ( jQuery.lastModified[ cacheURL ] ) {
				jqXHR.setRequestHeader( "If-Modified-Since", jQuery.lastModified[ cacheURL ] );
			}
			if ( jQuery.etag[ cacheURL ] ) {
				jqXHR.setRequestHeader( "If-None-Match", jQuery.etag[ cacheURL ] );
			}
		}

		// Set the correct header, if data is being sent
		if ( s.data && s.hasContent && s.contentType !== false || options.contentType ) {
			jqXHR.setRequestHeader( "Content-Type", s.contentType );
		}

		// Set the Accepts header for the server, depending on the dataType
		jqXHR.setRequestHeader(
			"Accept",
			s.dataTypes[ 0 ] && s.accepts[ s.dataTypes[ 0 ] ] ?
				s.accepts[ s.dataTypes[ 0 ] ] +
					( s.dataTypes[ 0 ] !== "*" ? ", " + allTypes + "; q=0.01" : "" ) :
				s.accepts[ "*" ]
		);

		// Check for headers option
		for ( i in s.headers ) {
			jqXHR.setRequestHeader( i, s.headers[ i ] );
		}

		// Allow custom headers/mimetypes and early abort
		if ( s.beforeSend &&
			( s.beforeSend.call( callbackContext, jqXHR, s ) === false || completed ) ) {

			// Abort if not done already and return
			return jqXHR.abort();
		}

		// Aborting is no longer a cancellation
		strAbort = "abort";

		// Install callbacks on deferreds
		completeDeferred.add( s.complete );
		jqXHR.done( s.success );
		jqXHR.fail( s.error );

		// Get transport
		transport = inspectPrefiltersOrTransports( transports, s, options, jqXHR );

		// If no transport, we auto-abort
		if ( !transport ) {
			done( -1, "No Transport" );
		} else {
			jqXHR.readyState = 1;

			// Send global event
			if ( fireGlobals ) {
				globalEventContext.trigger( "ajaxSend", [ jqXHR, s ] );
			}

			// If request was aborted inside ajaxSend, stop there
			if ( completed ) {
				return jqXHR;
			}

			// Timeout
			if ( s.async && s.timeout > 0 ) {
				timeoutTimer = window.setTimeout( function() {
					jqXHR.abort( "timeout" );
				}, s.timeout );
			}

			try {
				completed = false;
				transport.send( requestHeaders, done );
			} catch ( e ) {

				// Rethrow post-completion exceptions
				if ( completed ) {
					throw e;
				}

				// Propagate others as results
				done( -1, e );
			}
		}

		// Callback for when everything is done
		function done( status, nativeStatusText, responses, headers ) {
			var isSuccess, success, error, response, modified,
				statusText = nativeStatusText;

			// Ignore repeat invocations
			if ( completed ) {
				return;
			}

			completed = true;

			// Clear timeout if it exists
			if ( timeoutTimer ) {
				window.clearTimeout( timeoutTimer );
			}

			// Dereference transport for early garbage collection
			// (no matter how long the jqXHR object will be used)
			transport = undefined;

			// Cache response headers
			responseHeadersString = headers || "";

			// Set readyState
			jqXHR.readyState = status > 0 ? 4 : 0;

			// Determine if successful
			isSuccess = status >= 200 && status < 300 || status === 304;

			// Get response data
			if ( responses ) {
				response = ajaxHandleResponses( s, jqXHR, responses );
			}

			// Use a noop converter for missing script but not if jsonp
			if ( !isSuccess &&
				jQuery.inArray( "script", s.dataTypes ) > -1 &&
				jQuery.inArray( "json", s.dataTypes ) < 0 ) {
				s.converters[ "text script" ] = function() {};
			}

			// Convert no matter what (that way responseXXX fields are always set)
			response = ajaxConvert( s, response, jqXHR, isSuccess );

			// If successful, handle type chaining
			if ( isSuccess ) {

				// Set the If-Modified-Since and/or If-None-Match header, if in ifModified mode.
				if ( s.ifModified ) {
					modified = jqXHR.getResponseHeader( "Last-Modified" );
					if ( modified ) {
						jQuery.lastModified[ cacheURL ] = modified;
					}
					modified = jqXHR.getResponseHeader( "etag" );
					if ( modified ) {
						jQuery.etag[ cacheURL ] = modified;
					}
				}

				// if no content
				if ( status === 204 || s.type === "HEAD" ) {
					statusText = "nocontent";

				// if not modified
				} else if ( status === 304 ) {
					statusText = "notmodified";

				// If we have data, let's convert it
				} else {
					statusText = response.state;
					success = response.data;
					error = response.error;
					isSuccess = !error;
				}
			} else {

				// Extract error from statusText and normalize for non-aborts
				error = statusText;
				if ( status || !statusText ) {
					statusText = "error";
					if ( status < 0 ) {
						status = 0;
					}
				}
			}

			// Set data for the fake xhr object
			jqXHR.status = status;
			jqXHR.statusText = ( nativeStatusText || statusText ) + "";

			// Success/Error
			if ( isSuccess ) {
				deferred.resolveWith( callbackContext, [ success, statusText, jqXHR ] );
			} else {
				deferred.rejectWith( callbackContext, [ jqXHR, statusText, error ] );
			}

			// Status-dependent callbacks
			jqXHR.statusCode( statusCode );
			statusCode = undefined;

			if ( fireGlobals ) {
				globalEventContext.trigger( isSuccess ? "ajaxSuccess" : "ajaxError",
					[ jqXHR, s, isSuccess ? success : error ] );
			}

			// Complete
			completeDeferred.fireWith( callbackContext, [ jqXHR, statusText ] );

			if ( fireGlobals ) {
				globalEventContext.trigger( "ajaxComplete", [ jqXHR, s ] );

				// Handle the global AJAX counter
				if ( !( --jQuery.active ) ) {
					jQuery.event.trigger( "ajaxStop" );
				}
			}
		}

		return jqXHR;
	},

	getJSON: function( url, data, callback ) {
		return jQuery.get( url, data, callback, "json" );
	},

	getScript: function( url, callback ) {
		return jQuery.get( url, undefined, callback, "script" );
	}
} );

jQuery.each( [ "get", "post" ], function( _i, method ) {
	jQuery[ method ] = function( url, data, callback, type ) {

		// Shift arguments if data argument was omitted
		if ( isFunction( data ) ) {
			type = type || callback;
			callback = data;
			data = undefined;
		}

		// The url can be an options object (which then must have .url)
		return jQuery.ajax( jQuery.extend( {
			url: url,
			type: method,
			dataType: type,
			data: data,
			success: callback
		}, jQuery.isPlainObject( url ) && url ) );
	};
} );

jQuery.ajaxPrefilter( function( s ) {
	var i;
	for ( i in s.headers ) {
		if ( i.toLowerCase() === "content-type" ) {
			s.contentType = s.headers[ i ] || "";
		}
	}
} );


jQuery._evalUrl = function( url, options, doc ) {
	return jQuery.ajax( {
		url: url,

		// Make this explicit, since user can override this through ajaxSetup (#11264)
		type: "GET",
		dataType: "script",
		cache: true,
		async: false,
		global: false,

		// Only evaluate the response if it is successful (gh-4126)
		// dataFilter is not invoked for failure responses, so using it instead
		// of the default converter is kludgy but it works.
		converters: {
			"text script": function() {}
		},
		dataFilter: function( response ) {
			jQuery.globalEval( response, options, doc );
		}
	} );
};


jQuery.fn.extend( {
	wrapAll: function( html ) {
		var wrap;

		if ( this[ 0 ] ) {
			if ( isFunction( html ) ) {
				html = html.call( this[ 0 ] );
			}

			// The elements to wrap the target around
			wrap = jQuery( html, this[ 0 ].ownerDocument ).eq( 0 ).clone( true );

			if ( this[ 0 ].parentNode ) {
				wrap.insertBefore( this[ 0 ] );
			}

			wrap.map( function() {
				var elem = this;

				while ( elem.firstElementChild ) {
					elem = elem.firstElementChild;
				}

				return elem;
			} ).append( this );
		}

		return this;
	},

	wrapInner: function( html ) {
		if ( isFunction( html ) ) {
			return this.each( function( i ) {
				jQuery( this ).wrapInner( html.call( this, i ) );
			} );
		}

		return this.each( function() {
			var self = jQuery( this ),
				contents = self.contents();

			if ( contents.length ) {
				contents.wrapAll( html );

			} else {
				self.append( html );
			}
		} );
	},

	wrap: function( html ) {
		var htmlIsFunction = isFunction( html );

		return this.each( function( i ) {
			jQuery( this ).wrapAll( htmlIsFunction ? html.call( this, i ) : html );
		} );
	},

	unwrap: function( selector ) {
		this.parent( selector ).not( "body" ).each( function() {
			jQuery( this ).replaceWith( this.childNodes );
		} );
		return this;
	}
} );


jQuery.expr.pseudos.hidden = function( elem ) {
	return !jQuery.expr.pseudos.visible( elem );
};
jQuery.expr.pseudos.visible = function( elem ) {
	return !!( elem.offsetWidth || elem.offsetHeight || elem.getClientRects().length );
};




jQuery.ajaxSettings.xhr = function() {
	try {
		return new window.XMLHttpRequest();
	} catch ( e ) {}
};

var xhrSuccessStatus = {

		// File protocol always yields status code 0, assume 200
		0: 200,

		// Support: IE <=9 only
		// #1450: sometimes IE returns 1223 when it should be 204
		1223: 204
	},
	xhrSupported = jQuery.ajaxSettings.xhr();

support.cors = !!xhrSupported && ( "withCredentials" in xhrSupported );
support.ajax = xhrSupported = !!xhrSupported;

jQuery.ajaxTransport( function( options ) {
	var callback, errorCallback;

	// Cross domain only allowed if supported through XMLHttpRequest
	if ( support.cors || xhrSupported && !options.crossDomain ) {
		return {
			send: function( headers, complete ) {
				var i,
					xhr = options.xhr();

				xhr.open(
					options.type,
					options.url,
					options.async,
					options.username,
					options.password
				);

				// Apply custom fields if provided
				if ( options.xhrFields ) {
					for ( i in options.xhrFields ) {
						xhr[ i ] = options.xhrFields[ i ];
					}
				}

				// Override mime type if needed
				if ( options.mimeType && xhr.overrideMimeType ) {
					xhr.overrideMimeType( options.mimeType );
				}

				// X-Requested-With header
				// For cross-domain requests, seeing as conditions for a preflight are
				// akin to a jigsaw puzzle, we simply never set it to be sure.
				// (it can always be set on a per-request basis or even using ajaxSetup)
				// For same-domain requests, won't change header if already provided.
				if ( !options.crossDomain && !headers[ "X-Requested-With" ] ) {
					headers[ "X-Requested-With" ] = "XMLHttpRequest";
				}

				// Set headers
				for ( i in headers ) {
					xhr.setRequestHeader( i, headers[ i ] );
				}

				// Callback
				callback = function( type ) {
					return function() {
						if ( callback ) {
							callback = errorCallback = xhr.onload =
								xhr.onerror = xhr.onabort = xhr.ontimeout =
									xhr.onreadystatechange = null;

							if ( type === "abort" ) {
								xhr.abort();
							} else if ( type === "error" ) {

								// Support: IE <=9 only
								// On a manual native abort, IE9 throws
								// errors on any property access that is not readyState
								if ( typeof xhr.status !== "number" ) {
									complete( 0, "error" );
								} else {
									complete(

										// File: protocol always yields status 0; see #8605, #14207
										xhr.status,
										xhr.statusText
									);
								}
							} else {
								complete(
									xhrSuccessStatus[ xhr.status ] || xhr.status,
									xhr.statusText,

									// Support: IE <=9 only
									// IE9 has no XHR2 but throws on binary (trac-11426)
									// For XHR2 non-text, let the caller handle it (gh-2498)
									( xhr.responseType || "text" ) !== "text"  ||
									typeof xhr.responseText !== "string" ?
										{ binary: xhr.response } :
										{ text: xhr.responseText },
									xhr.getAllResponseHeaders()
								);
							}
						}
					};
				};

				// Listen to events
				xhr.onload = callback();
				errorCallback = xhr.onerror = xhr.ontimeout = callback( "error" );

				// Support: IE 9 only
				// Use onreadystatechange to replace onabort
				// to handle uncaught aborts
				if ( xhr.onabort !== undefined ) {
					xhr.onabort = errorCallback;
				} else {
					xhr.onreadystatechange = function() {

						// Check readyState before timeout as it changes
						if ( xhr.readyState === 4 ) {

							// Allow onerror to be called first,
							// but that will not handle a native abort
							// Also, save errorCallback to a variable
							// as xhr.onerror cannot be accessed
							window.setTimeout( function() {
								if ( callback ) {
									errorCallback();
								}
							} );
						}
					};
				}

				// Create the abort callback
				callback = callback( "abort" );

				try {

					// Do send the request (this may raise an exception)
					xhr.send( options.hasContent && options.data || null );
				} catch ( e ) {

					// #14683: Only rethrow if this hasn't been notified as an error yet
					if ( callback ) {
						throw e;
					}
				}
			},

			abort: function() {
				if ( callback ) {
					callback();
				}
			}
		};
	}
} );




// Prevent auto-execution of scripts when no explicit dataType was provided (See gh-2432)
jQuery.ajaxPrefilter( function( s ) {
	if ( s.crossDomain ) {
		s.contents.script = false;
	}
} );

// Install script dataType
jQuery.ajaxSetup( {
	accepts: {
		script: "text/javascript, application/javascript, " +
			"application/ecmascript, application/x-ecmascript"
	},
	contents: {
		script: /\b(?:java|ecma)script\b/
	},
	converters: {
		"text script": function( text ) {
			jQuery.globalEval( text );
			return text;
		}
	}
} );

// Handle cache's special case and crossDomain
jQuery.ajaxPrefilter( "script", function( s ) {
	if ( s.cache === undefined ) {
		s.cache = false;
	}
	if ( s.crossDomain ) {
		s.type = "GET";
	}
} );

// Bind script tag hack transport
jQuery.ajaxTransport( "script", function( s ) {

	// This transport only deals with cross domain or forced-by-attrs requests
	if ( s.crossDomain || s.scriptAttrs ) {
		var script, callback;
		return {
			send: function( _, complete ) {
				script = jQuery( "<script>" )
					.attr( s.scriptAttrs || {} )
					.prop( { charset: s.scriptCharset, src: s.url } )
					.on( "load error", callback = function( evt ) {
						script.remove();
						callback = null;
						if ( evt ) {
							complete( evt.type === "error" ? 404 : 200, evt.type );
						}
					} );

				// Use native DOM manipulation to avoid our domManip AJAX trickery
				document.head.appendChild( script[ 0 ] );
			},
			abort: function() {
				if ( callback ) {
					callback();
				}
			}
		};
	}
} );




var oldCallbacks = [],
	rjsonp = /(=)\?(?=&|$)|\?\?/;

// Default jsonp settings
jQuery.ajaxSetup( {
	jsonp: "callback",
	jsonpCallback: function() {
		var callback = oldCallbacks.pop() || ( jQuery.expando + "_" + ( nonce.guid++ ) );
		this[ callback ] = true;
		return callback;
	}
} );

// Detect, normalize options and install callbacks for jsonp requests
jQuery.ajaxPrefilter( "json jsonp", function( s, originalSettings, jqXHR ) {

	var callbackName, overwritten, responseContainer,
		jsonProp = s.jsonp !== false && ( rjsonp.test( s.url ) ?
			"url" :
			typeof s.data === "string" &&
				( s.contentType || "" )
					.indexOf( "application/x-www-form-urlencoded" ) === 0 &&
				rjsonp.test( s.data ) && "data"
		);

	// Handle iff the expected data type is "jsonp" or we have a parameter to set
	if ( jsonProp || s.dataTypes[ 0 ] === "jsonp" ) {

		// Get callback name, remembering preexisting value associated with it
		callbackName = s.jsonpCallback = isFunction( s.jsonpCallback ) ?
			s.jsonpCallback() :
			s.jsonpCallback;

		// Insert callback into url or form data
		if ( jsonProp ) {
			s[ jsonProp ] = s[ jsonProp ].replace( rjsonp, "$1" + callbackName );
		} else if ( s.jsonp !== false ) {
			s.url += ( rquery.test( s.url ) ? "&" : "?" ) + s.jsonp + "=" + callbackName;
		}

		// Use data converter to retrieve json after script execution
		s.converters[ "script json" ] = function() {
			if ( !responseContainer ) {
				jQuery.error( callbackName + " was not called" );
			}
			return responseContainer[ 0 ];
		};

		// Force json dataType
		s.dataTypes[ 0 ] = "json";

		// Install callback
		overwritten = window[ callbackName ];
		window[ callbackName ] = function() {
			responseContainer = arguments;
		};

		// Clean-up function (fires after converters)
		jqXHR.always( function() {

			// If previous value didn't exist - remove it
			if ( overwritten === undefined ) {
				jQuery( window ).removeProp( callbackName );

			// Otherwise restore preexisting value
			} else {
				window[ callbackName ] = overwritten;
			}

			// Save back as free
			if ( s[ callbackName ] ) {

				// Make sure that re-using the options doesn't screw things around
				s.jsonpCallback = originalSettings.jsonpCallback;

				// Save the callback name for future use
				oldCallbacks.push( callbackName );
			}

			// Call if it was a function and we have a response
			if ( responseContainer && isFunction( overwritten ) ) {
				overwritten( responseContainer[ 0 ] );
			}

			responseContainer = overwritten = undefined;
		} );

		// Delegate to script
		return "script";
	}
} );




// Support: Safari 8 only
// In Safari 8 documents created via document.implementation.createHTMLDocument
// collapse sibling forms: the second one becomes a child of the first one.
// Because of that, this security measure has to be disabled in Safari 8.
// https://bugs.webkit.org/show_bug.cgi?id=137337
support.createHTMLDocument = ( function() {
	var body = document.implementation.createHTMLDocument( "" ).body;
	body.innerHTML = "<form></form><form></form>";
	return body.childNodes.length === 2;
} )();


// Argument "data" should be string of html
// context (optional): If specified, the fragment will be created in this context,
// defaults to document
// keepScripts (optional): If true, will include scripts passed in the html string
jQuery.parseHTML = function( data, context, keepScripts ) {
	if ( typeof data !== "string" ) {
		return [];
	}
	if ( typeof context === "boolean" ) {
		keepScripts = context;
		context = false;
	}

	var base, parsed, scripts;

	if ( !context ) {

		// Stop scripts or inline event handlers from being executed immediately
		// by using document.implementation
		if ( support.createHTMLDocument ) {
			context = document.implementation.createHTMLDocument( "" );

			// Set the base href for the created document
			// so any parsed elements with URLs
			// are based on the document's URL (gh-2965)
			base = context.createElement( "base" );
			base.href = document.location.href;
			context.head.appendChild( base );
		} else {
			context = document;
		}
	}

	parsed = rsingleTag.exec( data );
	scripts = !keepScripts && [];

	// Single tag
	if ( parsed ) {
		return [ context.createElement( parsed[ 1 ] ) ];
	}

	parsed = buildFragment( [ data ], context, scripts );

	if ( scripts && scripts.length ) {
		jQuery( scripts ).remove();
	}

	return jQuery.merge( [], parsed.childNodes );
};


/**
 * Load a url into a page
 */
jQuery.fn.load = function( url, params, callback ) {
	var selector, type, response,
		self = this,
		off = url.indexOf( " " );

	if ( off > -1 ) {
		selector = stripAndCollapse( url.slice( off ) );
		url = url.slice( 0, off );
	}

	// If it's a function
	if ( isFunction( params ) ) {

		// We assume that it's the callback
		callback = params;
		params = undefined;

	// Otherwise, build a param string
	} else if ( params && typeof params === "object" ) {
		type = "POST";
	}

	// If we have elements to modify, make the request
	if ( self.length > 0 ) {
		jQuery.ajax( {
			url: url,

			// If "type" variable is undefined, then "GET" method will be used.
			// Make value of this field explicit since
			// user can override it through ajaxSetup method
			type: type || "GET",
			dataType: "html",
			data: params
		} ).done( function( responseText ) {

			// Save response for use in complete callback
			response = arguments;

			self.html( selector ?

				// If a selector was specified, locate the right elements in a dummy div
				// Exclude scripts to avoid IE 'Permission Denied' errors
				jQuery( "<div>" ).append( jQuery.parseHTML( responseText ) ).find( selector ) :

				// Otherwise use the full result
				responseText );

		// If the request succeeds, this function gets "data", "status", "jqXHR"
		// but they are ignored because response was set above.
		// If it fails, this function gets "jqXHR", "status", "error"
		} ).always( callback && function( jqXHR, status ) {
			self.each( function() {
				callback.apply( this, response || [ jqXHR.responseText, status, jqXHR ] );
			} );
		} );
	}

	return this;
};




jQuery.expr.pseudos.animated = function( elem ) {
	return jQuery.grep( jQuery.timers, function( fn ) {
		return elem === fn.elem;
	} ).length;
};




jQuery.offset = {
	setOffset: function( elem, options, i ) {
		var curPosition, curLeft, curCSSTop, curTop, curOffset, curCSSLeft, calculatePosition,
			position = jQuery.css( elem, "position" ),
			curElem = jQuery( elem ),
			props = {};

		// Set position first, in-case top/left are set even on static elem
		if ( position === "static" ) {
			elem.style.position = "relative";
		}

		curOffset = curElem.offset();
		curCSSTop = jQuery.css( elem, "top" );
		curCSSLeft = jQuery.css( elem, "left" );
		calculatePosition = ( position === "absolute" || position === "fixed" ) &&
			( curCSSTop + curCSSLeft ).indexOf( "auto" ) > -1;

		// Need to be able to calculate position if either
		// top or left is auto and position is either absolute or fixed
		if ( calculatePosition ) {
			curPosition = curElem.position();
			curTop = curPosition.top;
			curLeft = curPosition.left;

		} else {
			curTop = parseFloat( curCSSTop ) || 0;
			curLeft = parseFloat( curCSSLeft ) || 0;
		}

		if ( isFunction( options ) ) {

			// Use jQuery.extend here to allow modification of coordinates argument (gh-1848)
			options = options.call( elem, i, jQuery.extend( {}, curOffset ) );
		}

		if ( options.top != null ) {
			props.top = ( options.top - curOffset.top ) + curTop;
		}
		if ( options.left != null ) {
			props.left = ( options.left - curOffset.left ) + curLeft;
		}

		if ( "using" in options ) {
			options.using.call( elem, props );

		} else {
			curElem.css( props );
		}
	}
};

jQuery.fn.extend( {

	// offset() relates an element's border box to the document origin
	offset: function( options ) {

		// Preserve chaining for setter
		if ( arguments.length ) {
			return options === undefined ?
				this :
				this.each( function( i ) {
					jQuery.offset.setOffset( this, options, i );
				} );
		}

		var rect, win,
			elem = this[ 0 ];

		if ( !elem ) {
			return;
		}

		// Return zeros for disconnected and hidden (display: none) elements (gh-2310)
		// Support: IE <=11 only
		// Running getBoundingClientRect on a
		// disconnected node in IE throws an error
		if ( !elem.getClientRects().length ) {
			return { top: 0, left: 0 };
		}

		// Get document-relative position by adding viewport scroll to viewport-relative gBCR
		rect = elem.getBoundingClientRect();
		win = elem.ownerDocument.defaultView;
		return {
			top: rect.top + win.pageYOffset,
			left: rect.left + win.pageXOffset
		};
	},

	// position() relates an element's margin box to its offset parent's padding box
	// This corresponds to the behavior of CSS absolute positioning
	position: function() {
		if ( !this[ 0 ] ) {
			return;
		}

		var offsetParent, offset, doc,
			elem = this[ 0 ],
			parentOffset = { top: 0, left: 0 };

		// position:fixed elements are offset from the viewport, which itself always has zero offset
		if ( jQuery.css( elem, "position" ) === "fixed" ) {

			// Assume position:fixed implies availability of getBoundingClientRect
			offset = elem.getBoundingClientRect();

		} else {
			offset = this.offset();

			// Account for the *real* offset parent, which can be the document or its root element
			// when a statically positioned element is identified
			doc = elem.ownerDocument;
			offsetParent = elem.offsetParent || doc.documentElement;
			while ( offsetParent &&
				( offsetParent === doc.body || offsetParent === doc.documentElement ) &&
				jQuery.css( offsetParent, "position" ) === "static" ) {

				offsetParent = offsetParent.parentNode;
			}
			if ( offsetParent && offsetParent !== elem && offsetParent.nodeType === 1 ) {

				// Incorporate borders into its offset, since they are outside its content origin
				parentOffset = jQuery( offsetParent ).offset();
				parentOffset.top += jQuery.css( offsetParent, "borderTopWidth", true );
				parentOffset.left += jQuery.css( offsetParent, "borderLeftWidth", true );
			}
		}

		// Subtract parent offsets and element margins
		return {
			top: offset.top - parentOffset.top - jQuery.css( elem, "marginTop", true ),
			left: offset.left - parentOffset.left - jQuery.css( elem, "marginLeft", true )
		};
	},

	// This method will return documentElement in the following cases:
	// 1) For the element inside the iframe without offsetParent, this method will return
	//    documentElement of the parent window
	// 2) For the hidden or detached element
	// 3) For body or html element, i.e. in case of the html node - it will return itself
	//
	// but those exceptions were never presented as a real life use-cases
	// and might be considered as more preferable results.
	//
	// This logic, however, is not guaranteed and can change at any point in the future
	offsetParent: function() {
		return this.map( function() {
			var offsetParent = this.offsetParent;

			while ( offsetParent && jQuery.css( offsetParent, "position" ) === "static" ) {
				offsetParent = offsetParent.offsetParent;
			}

			return offsetParent || documentElement;
		} );
	}
} );

// Create scrollLeft and scrollTop methods
jQuery.each( { scrollLeft: "pageXOffset", scrollTop: "pageYOffset" }, function( method, prop ) {
	var top = "pageYOffset" === prop;

	jQuery.fn[ method ] = function( val ) {
		return access( this, function( elem, method, val ) {

			// Coalesce documents and windows
			var win;
			if ( isWindow( elem ) ) {
				win = elem;
			} else if ( elem.nodeType === 9 ) {
				win = elem.defaultView;
			}

			if ( val === undefined ) {
				return win ? win[ prop ] : elem[ method ];
			}

			if ( win ) {
				win.scrollTo(
					!top ? val : win.pageXOffset,
					top ? val : win.pageYOffset
				);

			} else {
				elem[ method ] = val;
			}
		}, method, val, arguments.length );
	};
} );

// Support: Safari <=7 - 9.1, Chrome <=37 - 49
// Add the top/left cssHooks using jQuery.fn.position
// Webkit bug: https://bugs.webkit.org/show_bug.cgi?id=29084
// Blink bug: https://bugs.chromium.org/p/chromium/issues/detail?id=589347
// getComputedStyle returns percent when specified for top/left/bottom/right;
// rather than make the css module depend on the offset module, just check for it here
jQuery.each( [ "top", "left" ], function( _i, prop ) {
	jQuery.cssHooks[ prop ] = addGetHookIf( support.pixelPosition,
		function( elem, computed ) {
			if ( computed ) {
				computed = curCSS( elem, prop );

				// If curCSS returns percentage, fallback to offset
				return rnumnonpx.test( computed ) ?
					jQuery( elem ).position()[ prop ] + "px" :
					computed;
			}
		}
	);
} );


// Create innerHeight, innerWidth, height, width, outerHeight and outerWidth methods
jQuery.each( { Height: "height", Width: "width" }, function( name, type ) {
	jQuery.each( {
		padding: "inner" + name,
		content: type,
		"": "outer" + name
	}, function( defaultExtra, funcName ) {

		// Margin is only for outerHeight, outerWidth
		jQuery.fn[ funcName ] = function( margin, value ) {
			var chainable = arguments.length && ( defaultExtra || typeof margin !== "boolean" ),
				extra = defaultExtra || ( margin === true || value === true ? "margin" : "border" );

			return access( this, function( elem, type, value ) {
				var doc;

				if ( isWindow( elem ) ) {

					// $( window ).outerWidth/Height return w/h including scrollbars (gh-1729)
					return funcName.indexOf( "outer" ) === 0 ?
						elem[ "inner" + name ] :
						elem.document.documentElement[ "client" + name ];
				}

				// Get document width or height
				if ( elem.nodeType === 9 ) {
					doc = elem.documentElement;

					// Either scroll[Width/Height] or offset[Width/Height] or client[Width/Height],
					// whichever is greatest
					return Math.max(
						elem.body[ "scroll" + name ], doc[ "scroll" + name ],
						elem.body[ "offset" + name ], doc[ "offset" + name ],
						doc[ "client" + name ]
					);
				}

				return value === undefined ?

					// Get width or height on the element, requesting but not forcing parseFloat
					jQuery.css( elem, type, extra ) :

					// Set width or height on the element
					jQuery.style( elem, type, value, extra );
			}, type, chainable ? margin : undefined, chainable );
		};
	} );
} );


jQuery.each( [
	"ajaxStart",
	"ajaxStop",
	"ajaxComplete",
	"ajaxError",
	"ajaxSuccess",
	"ajaxSend"
], function( _i, type ) {
	jQuery.fn[ type ] = function( fn ) {
		return this.on( type, fn );
	};
} );




jQuery.fn.extend( {

	bind: function( types, data, fn ) {
		return this.on( types, null, data, fn );
	},
	unbind: function( types, fn ) {
		return this.off( types, null, fn );
	},

	delegate: function( selector, types, data, fn ) {
		return this.on( types, selector, data, fn );
	},
	undelegate: function( selector, types, fn ) {

		// ( namespace ) or ( selector, types [, fn] )
		return arguments.length === 1 ?
			this.off( selector, "**" ) :
			this.off( types, selector || "**", fn );
	},

	hover: function( fnOver, fnOut ) {
		return this.mouseenter( fnOver ).mouseleave( fnOut || fnOver );
	}
} );

jQuery.each(
	( "blur focus focusin focusout resize scroll click dblclick " +
	"mousedown mouseup mousemove mouseover mouseout mouseenter mouseleave " +
	"change select submit keydown keypress keyup contextmenu" ).split( " " ),
	function( _i, name ) {

		// Handle event binding
		jQuery.fn[ name ] = function( data, fn ) {
			return arguments.length > 0 ?
				this.on( name, null, data, fn ) :
				this.trigger( name );
		};
	}
);




// Support: Android <=4.0 only
// Make sure we trim BOM and NBSP
var rtrim = /^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$/g;

// Bind a function to a context, optionally partially applying any
// arguments.
// jQuery.proxy is deprecated to promote standards (specifically Function#bind)
// However, it is not slated for removal any time soon
jQuery.proxy = function( fn, context ) {
	var tmp, args, proxy;

	if ( typeof context === "string" ) {
		tmp = fn[ context ];
		context = fn;
		fn = tmp;
	}

	// Quick check to determine if target is callable, in the spec
	// this throws a TypeError, but we will just return undefined.
	if ( !isFunction( fn ) ) {
		return undefined;
	}

	// Simulated bind
	args = slice.call( arguments, 2 );
	proxy = function() {
		return fn.apply( context || this, args.concat( slice.call( arguments ) ) );
	};

	// Set the guid of unique handler to the same of original handler, so it can be removed
	proxy.guid = fn.guid = fn.guid || jQuery.guid++;

	return proxy;
};

jQuery.holdReady = function( hold ) {
	if ( hold ) {
		jQuery.readyWait++;
	} else {
		jQuery.ready( true );
	}
};
jQuery.isArray = Array.isArray;
jQuery.parseJSON = JSON.parse;
jQuery.nodeName = nodeName;
jQuery.isFunction = isFunction;
jQuery.isWindow = isWindow;
jQuery.camelCase = camelCase;
jQuery.type = toType;

jQuery.now = Date.now;

jQuery.isNumeric = function( obj ) {

	// As of jQuery 3.0, isNumeric is limited to
	// strings and numbers (primitives or objects)
	// that can be coerced to finite numbers (gh-2662)
	var type = jQuery.type( obj );
	return ( type === "number" || type === "string" ) &&

		// parseFloat NaNs numeric-cast false positives ("")
		// ...but misinterprets leading-number strings, particularly hex literals ("0x...")
		// subtraction forces infinities to NaN
		!isNaN( obj - parseFloat( obj ) );
};

jQuery.trim = function( text ) {
	return text == null ?
		"" :
		( text + "" ).replace( rtrim, "" );
};



// Register as a named AMD module, since jQuery can be concatenated with other
// files that may use define, but not via a proper concatenation script that
// understands anonymous AMD modules. A named AMD is safest and most robust
// way to register. Lowercase jquery is used because AMD module names are
// derived from file names, and jQuery is normally delivered in a lowercase
// file name. Do this after creating the global so that if an AMD module wants
// to call noConflict to hide this version of jQuery, it will work.

// Note that for maximum portability, libraries that are not jQuery should
// declare themselves as anonymous modules, and avoid setting a global if an
// AMD loader is present. jQuery is a special case. For more information, see
// https://github.com/jrburke/requirejs/wiki/Updating-existing-libraries#wiki-anon

if ( typeof define === "function" && define.amd ) {
	define( "jquery", [], function() {
		return jQuery;
	} );
}




var

	// Map over jQuery in case of overwrite
	_jQuery = window.jQuery,

	// Map over the $ in case of overwrite
	_$ = window.$;

jQuery.noConflict = function( deep ) {
	if ( window.$ === jQuery ) {
		window.$ = _$;
	}

	if ( deep && window.jQuery === jQuery ) {
		window.jQuery = _jQuery;
	}

	return jQuery;
};

// Expose jQuery and $ identifiers, even in AMD
// (#7102#comment:10, https://github.com/jquery/jquery/pull/557)
// and CommonJS for browser emulators (#13566)
if ( typeof noGlobal === "undefined" ) {
	window.jQuery = window.$ = jQuery;
}




return jQuery;
} );

//--- end /usr/local/cpanel/base/cjt/jquery.js ---

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
