/*
# cjt/util/promise.js                                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * promise.js - Promise creator abstraction
 *
 * This abstracts over native Promise so that using IE11 isn’t as awkward.
 * ----------------------------------------------------------------------
 *
 * EXAMPLE USAGE:
 *
 * // Just like native Promise …
 * var promise = PROMISE.create( function(resolve, reject) { ... } );
 *
 * ----------------------------------------------------------------------
 */

// NB: The fact that this uses jQuery is an implementation detail.
// It could just as easily use a polyfill or some other solution.
define(["jquery"], function(jQ) {
    "use strict";

    var _module;

    function create( promiseCallback ) {
        var promise;

        if (_module._Promise) {
            promise = new _module._Promise(promiseCallback);
        } else {
            var deferred = jQ.Deferred();
            var res = function(obj) {
                deferred.resolveWith(window, [obj]);
            };
            var rej = function(obj) {
                deferred.rejectWith(window, [obj]);
            };
            promiseCallback(res, rej);

            promise = deferred.promise();
        }

        return promise;
    }

    _module = {
        MODULE_NAME: "cjt/util/promise",
        MODULE_DESC: "Native Promise wrapper",
        MODULE_VERSION: "1.0",

        create: create,

        // for testing
        _Promise: window.Promise,
    };

    return _module;
});
