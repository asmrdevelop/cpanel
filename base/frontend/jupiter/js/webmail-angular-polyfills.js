// Copyright 2024 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

// Work around CPANEL.api not existing by reimplementing it in pure JS
window.CPANEL = {
    "api": function(argsHr) {
        "use strict";

        // Validate parking/args, construct URI
        if ( !Object.keys(argsHr).includes("module", "func", "version") ) {

            // Alert the caller to the issue
            throw "window.CPANEL.api() requires the following args: 'module', 'func', 'version'";
        }
        if (!window.cp_security_token) {
            throw "cp_security_token not set in window. Can't execute calls.";
        }
        let apiUri = window.cp_security_token + "/execute/" + argsHr["module"] + "/" + argsHr["func"] + "?api.version=" + argsHr["version"];

        // Technically should parse args here, but only requester does not
        // provide them, so not going to do till there's a need.

        const req = new XMLHttpRequest();
        req.responseType = "json";
        req.onreadystatechange = function() {
            if (req && req.readyState === XMLHttpRequest.DONE) {
                if ( req.status === 0 || ( req.status >= 200 && req.status < 400 ) ) {
                    if ( argsHr["callback"] && typeof argsHr["callback"] === "object" && argsHr["callback"]["success"] ) {
                        let respObj = {
                            "cpanel_raw": req.response,
                            "cpanel_status": req.response.status,
                            "cpanel_data": req.response.data,
                            "cpanel_error": req.response.errors,
                            "cpanel_warnings": req.response.warnings,
                            "cpanel_messages": req.response.messages,
                            "cpanel_metadata": req.response.metadata,
                        };
                        argsHr.callback.success(respObj);
                    }
                } else {
                    if ( argsHr["callback"] && typeof argsHr["callback"] === "object" && argsHr["callback"]["error"] ) {

                        // Do what they told you to do in the CBs for error
                        argsHr.callback.error(req);
                    }
                }
            }
        };
        req.open( "GET", apiUri );
        req.send();
        return req;
    },
};

// Partially define window.LOCALE for format_bytes, cheat to do it via Intl
window.LOCALE = {
    format_bytes: function(bytes, decimalPlaces) {
        "use strict";
        var dataAbbreviations = ["KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
        if (decimalPlaces === undefined) {
            decimalPlaces = 2;
        }
        bytes = Number(bytes);
        var exponent = bytes && Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), dataAbbreviations.length);
        if (!exponent) {
            return bytes + " B";
        } else {

            // Format decimal places, as Intl does not do this for you.
            bytes = parseFloat(bytes / Math.pow(1024, exponent)).toFixed(decimalPlaces);
            return Intl.NumberFormat().format(bytes) + "\u00a0" + dataAbbreviations[exponent - 1];
        }
    },
};
