/*
# cjt/io/eventsource.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * eventsource.js - Quick and easy EventSource!
 * ----------------------------------------------------------------------
 *
 * EXAMPLE USAGE:
 *
 *  // same args as native EventSource constructor
 *  EVENTSOURCE.create( "/url/to/sse/stream", config ).then(
 *      (evt) => { ... },    // evt.target is your EventSource instance
 *      (errObj) => { ... }
 *  } );
 *
 * ----------------------------------------------------------------------
 *
 * This library solves two problems:
 *
 * 1) Microsoft browsers (including Edge) lack native EventSource support.
 *  cf. https://developer.microsoft.com/en-us/microsoft-edge/platform/status/serversenteventseventsource/
 *
 * 2) Turn EventSource’s indication of initial connection success/failure
 *  into a nice, friendly promise.
 *
 */

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

define( [
    "cjt/util/getScript",
    "cjt/util/promise",
], function(GETSCRIPT, PROMISE) {
    "use strict";

    var _ES;

    function _returnEvtSrcPromise(url, config) {
        return PROMISE.create( function(res, rej) {
            var es = new _ES._EventSource(url, config);

            function _onError(e) {
                _clearListeners();
                rej(e);
            }

            function _onOpen(e) {
                _clearListeners();
                res(e);
            }

            function _clearListeners() {
                es.removeEventListener("open", _onOpen);
                es.removeEventListener("error", _onError);
            }

            es.addEventListener("open", _onOpen);
            es.addEventListener("error", _onError);
        } );
    }

    function _create(url, config) {
        if (_ES._EventSource) {
            return _returnEvtSrcPromise(url, config);
        } else {
            var ctx = {};

            var polyfill = GETSCRIPT.getScript(
                _ES._POLYFILL_URL,
                { context: ctx }
            );

            return polyfill.then( function() {
                _ES._EventSource = ctx.EventSource;
                return _returnEvtSrcPromise(url, config);
            } );
        }
    }

    _ES = {
        MODULE_NAME: "cjt/io/eventsource",
        MODULE_DESC: "EventSource wrapper with promise",
        MODULE_VERSION: "1.0",

        // to facilitate mocking
        _EventSource: window.EventSource,
        _POLYFILL_URL: "/libraries/eventsource-polyfill/eventsource.js",

        create: _create,
    };

    return _ES;
} );
