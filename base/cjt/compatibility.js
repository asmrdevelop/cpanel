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
