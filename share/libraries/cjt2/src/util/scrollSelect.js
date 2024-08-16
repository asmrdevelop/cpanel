/*
# cjt/util/scrollSelect.js                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

// Expand this later as necessary to include metadata.
define([], function() {
    "use strict";

    return {
        MODULE_NAME: "cjt/io/scrollSelect",
        MODULE_DESC: "Utilities for scrolling a DOM <select> node",
        MODULE_VERSION: "1.0",

        scrollToEnd: function(el) {
            el.scrollTop = el.scrollHeight;
        },

        // copied from base/sharedjs/transfers/TransferLogRender.js
        isAtEnd: function(el) {
            return (el.scrollTop + el.offsetHeight + 1 >= el.scrollHeight) || (el.scrollHeight <= el.offsetHeight);
        },
    };
} );
