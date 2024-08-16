/*
# cjt/util/html.js                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define([
    "jquery"
],
function($) {


    return {

        /**
             * Encode a value as html.
             *
             * @static
             * @method encode
             * @param  {String} value String with html characters that need encoding
             * @return {String}       Same string with html characters encoded.
             */
        encode: function(value) {

            // create a in-memory div, set it's inner text(which jQuery automatically encodes)
            // then grab the encoded contents back out.  The div never exists on the page.
            return $("<div/>").text(value).html();
        },

        /**
             * Decode a string from html encoding to text.
             *
             * @static
             * @method decode
             * @param  {String} value String with html encoded characters
             * @return {String}       Same string with html encoded characters decoded.
             */
        decode: function(value) {
            return $("<div/>").html(value).text();
        }
    };
}
);
