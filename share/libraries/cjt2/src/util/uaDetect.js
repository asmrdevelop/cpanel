/*
# cjt/util/uaDetect.js                            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/**
 * This module is meant to house user agent (UA) detection logic.
 *
 * Ordinarily we shouldn’t depend on things like this,
 * but there are some applications where there’s not a (known) better
 * alternative.
*/

define(
    function() {
        "use strict";

        var _UAD = {
            isMacintosh: function _isMacintosh() {
                return (_UAD.__window.navigator.platform.indexOf("Mac") === 0);
            },

            // for mocking
            __window: window,
        };

        return _UAD;
    }
);
