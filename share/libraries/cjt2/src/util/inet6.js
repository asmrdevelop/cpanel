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
