/*
# cjt/io/websocket.js                                Copyright 2022 cPanel, L.L.C.
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
define(["cjt/core"], function(CJT) {
    "use strict";

    // Taken from CPAN Net::WebSocket
    var _STATUS = {
        SUCCESS: 1000,
        ENDPOINT_UNAVAILABLE: 1001,
        PROTOCOL_ERROR: 1002,
        INVALID_DATA_TYPE: 1003,

        // These two never actually go over the wire,
        // but they’re how browsers report these conditions.
        EMPTY: 1005,
        ABORTED: 1006,

        INVALID_PAYLOAD: 1007,
        POLICY_VIOLATION: 1008,
        MESSAGE_TOO_BIG: 1009,
        UNSUPPORTED_EXTENSIONS: 1010,
        INTERNAL_ERROR: 1011,

        SERVICE_RESTART: 1012,
        TRY_AGAIN_LATER: 1013,
        BAD_GATEWAY: 1014,
    };

    var _WS = {
        MODULE_NAME: "cjt/io/websocket",
        MODULE_DESC: "WebSocket tools for cPanel UIs",
        MODULE_VERSION: "1.0",

        /**
        * A lookup of status name to code.
        * You’ll probably want this for the “SUCCESS” code.
        */
        STATUS: _STATUS,

        /**
        * Returns the “base” URL for a websocket app;
        * e.g., if the page URL is:
        *
        *   https://some.server:2087/cpsess12345678/app/index.html
        *
        * then this will give:
        *
        *   wss://some.server:2087/cpsess12345678
        */
        getUrlBase: function _getUrlBase() {
            var protocol = _WS.__window.location.protocol;

            if (/^https?:$/.test(protocol)) {
                protocol = protocol.replace(/^http/, "ws");
            } else {
                throw new Error( "Unknown “location.protocol”: [_]".replace(/_/, protocol) );
            }

            return protocol + "//" + _WS.__window.location.host + CJT.securityToken;
        },

        /**
        * Returns a nicely-formatted string from a non-SUCCESS
        * close event. This string is suitable to show in the UI.
        */
        getErrorString: function _getErrorString(event) {
            var name = this._getStatusName(event.code);
            var reason = event.reason;

            var str = name || event.code;

            if (reason) {
                str += ": " + reason;
            }

            return str;
        },

        // To facilitate mocking
        __window: window,

        _getStatusName: function _getStatusName(code) {
            for (var name in _STATUS) {
                if (_STATUS[name] === code) {
                    return name;
                }
            }
        },
    };

    return _WS;
} );
