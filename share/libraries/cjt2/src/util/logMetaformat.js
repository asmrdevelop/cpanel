/*
# cjt/util/logMetaformat.js                         Copyright 2022 cPanel, L.L.C.
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
        MODULE_NAME: "cjt/io/logMetaformat",
        MODULE_DESC: "Parser for the encoding of Cpanel::Log::MetaFormat",
        MODULE_VERSION: "1.0",

        parse: function(input, metadata) {
            input = input.replace(/\.(\.|[^.\n][^\n]*\n)/mg, function(match, p1) {
                if (p1 === ".") {
                    return ".";
                }

                var decoded = JSON.parse(p1);   // trailing newline is ok
                metadata[decoded[0]] = decoded[1];

                return "";
            });

            return input;
        },
    };
} );
