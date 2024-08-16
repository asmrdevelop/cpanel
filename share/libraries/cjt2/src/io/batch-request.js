/*
# cjt/io/batch-request.js                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * EXAMPLE USAGE:
 *
 *  // APIREQUEST is, e.g., io/uapi-request or io/whm-v1-request
 *  var call1 = new APIREQUEST.Class().initialize( .. );
 *  var call2 = new APIREQUEST.Class().initialize( .. );
 *
 *  var batch = new BATCH.Class( [call1, call2] );
 *
 *  // APICatcher is just used as an example here. Anything that would
 *  // accept “call1” or “call2” individually can also take “batch”.
 *  APICatcher.promise(batch).then( (resp) => {
 *
 *      // resp.data is an array that contains the individual
 *      // API calls’ response objects, so, e.g.:
 *
 *      if (!resp.data[0].parsedResponse.status) {
 *          throw "nonono";
 *      }
 *
 *      // .. and so on ..
 *  } );
 *
 * ----------------------------------------------------------------------
 *
 * This library ties into io/base’s batch-handling logic to give API
 * callers a seamless experience of batching API calls. This module handles
 * all of the formatting aspects of batched API calls automatically
 * so you can just write your API calls, and it “just works”. :)
 *
 */

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

// Expand this later as necessary to include metadata.
define(["lodash"], function(_) {
    "use strict";

    var BatchRequest = function( calls ) {
        calls = calls || [];
        this._runargs = [];

        // PhantomJS doesn’t have Function.prototype.bind still,
        // so use lodash’s wrapper. :-/
        calls.forEach( _.bind(this.add, this) );
    };

    _.extend(
        BatchRequest.prototype,
        {
            add: function(apiCallObj) {
                var run = apiCallObj.getRunArguments();
                if (this._last_version) {
                    if (this._last_version !== run.version) {
                        throw ( "Version mismatch! " + this._last_version + " vs. " + run.version );
                    }
                } else {
                    this._last_version = run.version;
                }

                this._runargs.push(run);

                return this;
            },

            getRunArguments: function() {
                if (!this._runargs.length) {
                    throw "Empty batch!";
                }

                return {
                    version: this._last_version,
                    batch: this._runargs
                };
            }
        }
    );

    return {
        MODULE_NAME: "cjt/io/batch-request",
        MODULE_DESC: "API-agnostic wrapper for batch API requests.",
        MODULE_VERSION: "1.0",
        Class: BatchRequest
    };
});
