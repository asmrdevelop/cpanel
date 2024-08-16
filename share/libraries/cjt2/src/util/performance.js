/*
# cjt/util/performance.js                         Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    function() {

        // ------------------------------------------------------------------------------
        // Developer Notes:
        // ------------------------------------------------------------------------------
        // This utility is provided to allow applications to depend on the performance
        // even in environments where the API does not exist such as Phantom.js. Note
        // if the environment does not have the API, the resolution is reduced
        // significantly since the resolution of Date.now() is not very good compared
        // to the high resolution time stamp used by the normal browser implementation.
        // ------------------------------------------------------------------------------

        var _performance;
        if (window && !window.performance) {
            _performance = {
                now: function() {
                    return Date.now();
                }
            };
        } else {
            _performance = window.performance;
        }


        return _performance;
    }
);
