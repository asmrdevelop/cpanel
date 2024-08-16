/*
# cjt/utils/limits.js                             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(function() {

    var UNLIMITED = -1,
        UNLIMITED_STR = "unlimited";


    return {
        UNLIMITED: UNLIMITED,
        UNLIMITED_STR: UNLIMITED_STR,

        /**
         * Parse a max limit
         * @param  {Object} limit [description]
         * @return {Number}       [description]
         */
        parseMaxLimit: function(limit) {
            if (!limit) {
                return 0;
            }
            return parseInt(limit.max === UNLIMITED_STR ? UNLIMITED : limit._max, 10);
        },

        /**
         * Retrieve the current count
         * @param  {Object} limit [description]
         * @return {Number}       [description]
         */
        parseTotalItems: function(limit) {
            if (!limit) {
                return 0;
            }
            return parseInt(limit._count, 10);
        },

        /**
         * Checks if a possibly unlimited value is in its limit.
         * @param  {Number} max     [description]
         * @param  {Number} current [description]
         * @return {Bool}         [description]
         */
        outOfLimits: function(max, current) {
            return (max !== UNLIMITED && current >= max);
        }
    };
});
