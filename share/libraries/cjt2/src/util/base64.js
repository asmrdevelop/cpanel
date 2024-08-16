/*
# cjt/util/base64.js                            Copyright(c) 2021 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    function() {
        "use strict";

        return {

            /**
             * @function decode
             *
             * A UTF-8-aware base64 decoder: it decodes base64 octets
             * to a JS string (each code point of which will be 0-255)
             * then decodes that string’s code points as UTF-8.
             *
             * This is nearly always preferable to the browser’s built-in
             * atob(), which only decodes the base64 octets without
             * the additional UTF-8 decoding step.
             *
             * @param b64 {string} The base64 text to decode.
             *
             * @return {string} The decoded text.
             */
            decodeUTF8: function(b64) {

                // This is slow, but it works. If more speed is necessary,
                // consider feeding the base64 to fetch() to get an array
                // buffer. Then use TextDecode on that buffer. (This will
                // be asynchronous, so it won’t work here.)
                //
                return decodeURIComponent(escape(atob(b64)));
            },
        };
    }
);
