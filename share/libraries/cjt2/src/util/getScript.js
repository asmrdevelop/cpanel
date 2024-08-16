/*
# cjt/util/getScript.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * EXAMPLE USAGE:
 *
 *  // same args as native EventSource constructor
 *  GETSCRIPT.getScript("/url/to/script", opts).then(
 *      (xhr) => ...
 *  ).catch( (err) => _handleFailure(err) );
 *
 * ----------------------------------------------------------------------
 *
 * NOTE: This runs the loaded JS in ES5 Strict Mode.
 *
 *
 * This library improves upon jQuery’s getScript() in a couple ways:
 *
 * 1) It’s pure JavaScript rather than jQuery’s approach of using DOM.
 *
 * 2) It reports network, HTTP, and parse errors via promise rejection.
 *
 *
 * require() can kind of do the work for this, but its error reporting
 * is inconsistent, and it doesn’t return a promise.
 *
 */

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

// jQuery for Promises
define(["cjt/util/promise"], function(PROMISE) {
    "use strict";

    var _module;

    /**
     * @function getScript
     *
     * @param url  {string} The URL of the JavaScript to load.
     *
     * @param opts {Object} Optional:
     *
     *  - context: The context in which to run the loaded JavaScript.
     *             Default is the window object.
     */
    function getScript(url, opts) {
        var ctx = opts && opts.context || window;

        return PROMISE.create( function(res, rej) {
            var xhr = new _module._XMLHttpRequest();

            xhr.addEventListener("load", function(e) {
                if (this.status === 200) {
                    var js = "'use strict'; " + this.responseText;
                    try {
                        Function(js).bind(ctx)();
                        res(e);
                    } catch (err) {
                        rej( new Error("Parse error (" + url + "): " + err) );
                    }
                } else {
                    rej( new Error("HTTP error (" + url + "): " + this.statusText) );
                }
            } );

            xhr.addEventListener("error", function(e) {
                rej( new Error("Network error (" + url + "): " + e));
            } );

            xhr.open("GET", url);
            xhr.send();
        } );
    }

    _module = {
        MODULE_NAME: "cjt/util/getScript",
        MODULE_DESC: "Improved version of jQuery getScript",
        MODULE_VERSION: "1.0",

        getScript: getScript,

        // for testing
        _XMLHttpRequest: window.XMLHttpRequest,
    };

    return _module;
});
