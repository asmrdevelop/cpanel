/*
# cjt/util/url.js                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(function() {
    return {

        /**
             * Join the path parts of the uri correctly making sure the slashes are
             * normalized correctly.
             *
             * @static
             * @method join
             * @param  {String...}    One or more url components to join together.
             * @return {String}       Valid url/uri path component.
             * @example
             * define(
             *     "cjt/util/url",
             *     function(URL)) {
             *         var url = URL.join("http://abc", "def", "ghi");
             *         assert(url === "http://abc/def/ghi");
             *
             *         url = URL.join("http://abc/", "/def", "/ghi");
             *         assert(url === "http://abc/def/ghi");
             *
             *         url = URL.join("http://abc/", "/def/", "/ghi/");
             *         assert(url === "http://abc/def/ghi/");
             *     }
             * );
             *
             */
        join: function() {
            var parts = [];
            for (var i = 0, l = arguments.length; i < l; i++) {
                var arg = arguments[i];

                // Only adjust inner / separators.

                // Assume the leading elements leading component is right
                if (i > 0) {
                    arg = arg.replace(/^[\/]/, "");
                }

                // Assume the trailing elements trailing component is right
                if (i !== l - 1) {
                    arg = arg.replace(/[\/]$/, "");
                }

                if (arg) {
                    parts.push(arg);
                }
            }
            return parts.join("/");
        }
    };
}
);
