/*
# cjt/io/appstream.js                                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

define(function() {
    "use strict";

    return {
        MODULE_NAME: "cjt/io/appstream",
        MODULE_DESC: "JavaScript implementation of the “AppStream” protocol, (cf. Cpanel::Server::WebSocket::AppStream)",
        MODULE_VERSION: "1.0",

        encodeDataPayload: function _encodeDataPayload(payload) {
            if (payload.indexOf(".") === 0) {
                payload = "." + payload;
            }

            return payload;
        },

        encodeControlPayload: function _encodeControlPayload(payload) {
            if (payload.indexOf(".") === 0) {
                throw new Error("control payload can’t start with “.”: " + payload);
            }

            return "." + payload;
        },
    };
} );
