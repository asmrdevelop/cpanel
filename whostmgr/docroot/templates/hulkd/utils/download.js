/*
# cpanel - whostmgr/docroot/templates/hulkd/utils/download.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
define(
    function() {

        "use strict";

        return {

            /**
             * Create a download name.
             *
             * @param {string} prefix
             * @returns {string}
             */
            getDownloadName: function(prefix) {
                return prefix + ".txt";
            },

            /**
             * Convert the raw data into a download url data blob.
             *
             * @param {string} data - the formatted download data.
             * @returns {string} - The data formatted for a download url.
             */
            getTextDownloadUrl: function(data) {
                var blob = new Blob([data], { type: "plain/text" });
                return window.URL.createObjectURL(blob);
            },

            /**
             * Clean up the allocated url.
             *
             * @param {string} url - the url previously created with createObjetURL.
             */
            cleanupDownloadUrl: function(url) {
                if (url) {
                    window.URL.revokeObjectURL(url);
                }
            },

            /**
             * @typedef IpRecord
             * @property {string} ip - ip address or range.
             * @property {string?} comment - comment associated with the ip or range.
             */

            /**
             * Convert the ip list into a serialized format.
             *
             * @param {IpRecord[]} list
             * @returns {string}
             */
            formatList: function(list) {
                if (list && list.length) {
                    return list.map(function(item) {
                        return item.ip + (item.comment ? " # " + item.comment : "");
                    }).join("\n") + "\n";
                }
                return "";
            },
        };

    }
);
