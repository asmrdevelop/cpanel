/*
# cjt/util/unicode.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "punycode",
],
function(PUNYCODE) {
    "use strict";

    var ucs2Encode = PUNYCODE.ucs2.encode;

    function _augmentLookup(cpArray, lookup, value, asCharYN) {
        for (var d = 0; d < cpArray.length; d++) {
            if (cpArray[d] instanceof Array) {
                for (var i = cpArray[d][0]; i <= cpArray[d][1]; i++) {
                    lookup[ asCharYN ? ucs2Encode([i]) : i ] = value;
                }
            } else {
                lookup[ asCharYN ? ucs2Encode( [cpArray[d]] ) : cpArray[d] ] = value;
            }
        }

        return lookup;
    }

    function createCharacterLookup(cpArray) {
        return _augmentLookup(cpArray, {}, true, true);
    }

    function augmentCodePointLookup(cpArray, lookup, value) {
        return _augmentLookup(cpArray, lookup, value, false);
    }

    return {
        createCharacterLookup: createCharacterLookup,
        augmentCodePointLookup: augmentCodePointLookup,
    };
} );
