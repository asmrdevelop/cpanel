/*
# cjt/util/string.js                               Copyright 2022 cPanel, L.L.C.
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
 *
 * @module cjt/util/string
 * @example
 *
 */
define(["lodash", "punycode"], function(_, PUNYCODE) {

    "use strict";

    // ------------------------------
    // Module
    // ------------------------------
    var MODULE_NAME = "cjt/util/string";
    var MODULE_DESC = "Contains string helper functions.";
    var MODULE_VERSION = 2.0;

    // Highest Unicode ASCII code point.
    var UNICODE_ASCII_CUTOFF = 127;

    // As of 2021 we no longer support any browsers that lack TextEncoder.
    var textEncoder = new TextEncoder();

    /**
     * Collection of string helper functions.
     *
     * @static
     * @public
     * @class String
     */
    var string = {
        MODULE_NAME: MODULE_NAME,
        MODULE_DESC: MODULE_DESC,
        MODULE_VERSION: MODULE_VERSION,

        /**
         * Left pads the string with leading characters. Will use spaces if
         * the padder parameter is not defined. Will pad with "0" if the padder
         * is 0.
         * @method  lpad
         * @param  {String} str    String to modify.
         * @param  {Number} len    Length of the padding.
         * @param  {String} padder Characters to pad with.
         * @return {String}        String padded to the full width defined by len parameter.
         */
        lpad: function(str, len, padder) {
            if (padder === 0) {
                padder = "0";
            } else if (!padder) {
                padder = " ";
            }

            var deficit = len - str.length;
            var pad = "";
            var padder_length = padder.length;
            while (deficit > 0) {
                pad += padder;
                deficit -= padder_length;
            }
            return pad + str;
        },

        /**
         * Reverse the characters in a string.
         * @param  {String} str  String to modify.
         * @return {String}      New string with characters reversed.
         */
        reverse: function(str) {

            // Can’t just do this because it mangles non-BMP characters:
            // return str.split("").reverse().join("");

            var codePoints = PUNYCODE.ucs2.decode(str);

            return PUNYCODE.ucs2.encode(codePoints.reverse());
        },

        /**
         * Returns the length, in bytes, of the string’s UTF-8 representation.
         *
         * @param  {String} str  String to examine.
         * @return {Number}      Byte count of the string in UTF-8.
         */
        getUTF8ByteCount: function getUTF8ByteCount(str) {
            return textEncoder.encode(str).length;
        },

        /**
         * Returns an array of the string’s unique non-ASCII characters.
         *
         * @param  {String} str  String to examine.
         * @return {String[]}    Array of 1-character strings.
         */
        getNonASCII: function getNonASCII(str) {
            var chars = [];

            // We can’t just iterate through the characters as JS sees them
            // because the string might contain non-BMP characters like emoji.

            var codePoints = PUNYCODE.ucs2.decode(str);

            for (var i = 0; i < codePoints.length; i++) {
                if (codePoints[i] > UNICODE_ASCII_CUTOFF) {
                    chars.push( PUNYCODE.ucs2.encode([codePoints[i]]) );
                }
            }

            return _.uniq(chars);
        },
    };

    return string;

});
