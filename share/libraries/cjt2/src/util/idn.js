/*
# cjt/util/idn.js                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * idn.js - IDN validation per RFC 5891/4.2
 *
 * This provides part of the IDN validation algorithm. Specifically,
 * this identifies:
 *
 *  - DISALLOWED characters
 *
 *  - improper hyphens
 *
 *  - most contextual rule violations
 *
 * This currently does NOT identify:
 *
 *  - UNASSIGNED characters
 *
 *  - leading combining marks
 *
 *  - certain contextual rules
 *
 *  - violations of Bidi criteria (RFC 5893/2)
 * ----------------------------------------------------------------------
 *
 * EXAMPLE USAGE:
 *
 * problemsStr = IDN.getLabelDefects( labelString )
 *
 * ----------------------------------------------------------------------
 */

define( [
    "lodash",
    "punycode",
    "cjt/util/locale",
    "cjt/util/idnDisallowed",
    "cjt/util/unicode",
],
function(_, PUNYCODE, LOCALE, IDN_DISALLOWED, UNICODE) {
    "use strict";

    // NB: many of the characters that fit these ranges are
    // also on IDN’s DISALLOWED list. The ranges below that
    // the DISALLOWED list fully excludes are commented out.
    //
    // We could edit the ranges that only partly overlap with the
    // DISALLOWED list, but that would make it harder to compare
    // our data with the upstream source. So partially-DISALLOWED
    // ranges are left in place.
    //
    // The lists of code points below come from:
    //  https://www.unicode.org/Public/12.1.0/ucd/Scripts.txt
    //
    // The most recent version will be at:
    //  https://www.unicode.org/Public/UCD/latest/ucd/Scripts.txt
    //
    // It may be useful at a later point to take steps to keep
    // these lists in sync with further revisions of that list.
    // For now we just publish static lists and hope that upstream
    // changes to these groups are rare.

    var SCRIPT_DATA = {
        greek: [
            [0x370, 0x373],
            0x375,
            [0x376, 0x377],

            // 0x37a,               // DISALLOWED
            [0x37b, 0x37d],
            0x37f,

            // 0x384,               // DISALLOWED
            // 0x386,               // DISALLOWED
            // [0x388, 0x38a],      // DISALLOWED
            // 0x38c,               // DISALLOWED
            [0x38e, 0x3a1],
            [0x3a3, 0x3e1],
            [0x3f0, 0x3f5],

            // 0x3f6,               // DISALLOWED
            [0x3f7, 0x3ff],
            [0x1d26, 0x1d2a],

            // [0x1d5d, 0x1d61],    // DISALLOWED
            // [0x1d66, 0x1d6a],    // DISALLOWED
            // 0x1dbf,              // DISALLOWED
            [0x1f00, 0x1f15],

            // [0x1f18, 0x1f1d],    // DISALLOWED
            [0x1f20, 0x1f45],

            // [0x1f48, 0x1f4d],    // DISALLOWED
            [0x1f50, 0x1f57],

            // 0x1f59,              // DISALLOWED
            // 0x1f5b,              // DISALLOWED
            // 0x1f5d,              // DISALLOWED
            [0x1f5f, 0x1f7d],
            [0x1f80, 0x1fb4],
            [0x1fb6, 0x1fbc],

            // 0x1fbd,              // DISALLOWED
            // 0x1fbe,              // DISALLOWED
            // [0x1fbf, 0x1fc1],    // DISALLOWED
            // [0x1fc2, 0x1fc4],    // DISALLOWED
            [0x1fc6, 0x1fcc],

            // [0x1fcd, 0x1fcf],    // DISALLOWED
            [0x1fd0, 0x1fd3],
            [0x1fd6, 0x1fdb],

            // [0x1fdd, 0x1fdf],    // DISALLOWED
            [0x1fe0, 0x1fec],

            // [0x1fed, 0x1fef],    // DISALLOWED
            // [0x1ff2, 0x1ff4],    // DISALLOWED
            [0x1ff6, 0x1ffc],

            // [0x1ffd, 0x1ffe],    // DISALLOWED
            // 0x2126,              // DISALLOWED
            0xab65,
            [0x10140, 0x10174],
            [0x10175, 0x10178],
            [0x10179, 0x10189],
            [0x1018a, 0x1018b],
            [0x1018c, 0x1018e],
            0x101a0,

            // [0x1d200, 0x1d241],  // DISALLOWED
            // [0x1d242, 0x1d244],  // DISALLOWED
            // 0x1d245,             // DISALLOWED
        ],

        hebrew: [
            [ 0x591, 0x5bd ],

            // 0x5be,               // DISALLOWED
            0x5bf,

            // 0x5c0,               // DISALLOWED
            [ 0x5c1, 0x5c2 ],

            // 0x5c3,               // DISALLOWED
            [ 0x5c4, 0x5c5 ],

            // 0x5c6,               // DISALLOWED
            0x5c7,
            [ 0x5d0, 0x5ea ],
            [ 0x5ef, 0x5f2 ],
            [ 0x5f3, 0x5f4 ],

            // 0xfb1d,              // DISALLOWED
            0xfb1e,

            // [ 0xfb1f, 0xfb28 ],  // DISALLOWED
            // 0xfb29,              // DISALLOWED
            // [ 0xfb2a, 0xfb36 ],  // DISALLOWED
            // [ 0xfb38, 0xfb3c ],  // DISALLOWED
            // 0xfb3e,              // DISALLOWED
            // [ 0xfb40, 0xfb41 ],  // DISALLOWED
            // [ 0xfb43, 0xfb44 ],  // DISALLOWED
            // [ 0xfb46, 0xfb4f ],  // DISALLOWED
        ],

        hiragana: [
            [ 0x3041, 0x3096 ],
            [ 0x309d, 0x309e ],

            // 0x309f,              // DISALLOWED
            [ 0x1b001, 0x1b11e ],
            [ 0x1b150, 0x1b152 ],

            // 0x1f200,             // DISALLOWED
        ],

        katakana: [
            [0x30a1, 0x30fa],
            [0x30fd, 0x30fe],

            // 0x30ff,              // DISALLOWED
            [0x31f0, 0x31ff],

            // [0x32d0, 0x32fe],    // DISALLOWED
            // [0x3300, 0x3357],    // DISALLOWED
            // [0xff66, 0xff6f],    // DISALLOWED
            // [0xff71, 0xff9d],    // DISALLOWED
            0x1b000,
            [0x1b164, 0x1b167],
        ],

        han: [

            // [0x2e80, 0x2e99],    // DISALLOWED
            // [0x2e9b, 0x2ef3],    // DISALLOWED
            // [0x2f00, 0x2fd5],    // DISALLOWED
            0x3005,
            0x3007,

            // [0x3021, 0x3029],    // DISALLOWED

            // [0x3038, 0x303a],    // DISALLOWED
            // 0x303b,              // DISALLOWED
            [0x3400, 0x4db5],
            [0x4e00, 0x9fef],
            [0xf900, 0xfa6d],

            // [0xfa70, 0xfad9],    // DISALLOWED
            [0x20000, 0x2a6d6],
            [0x2a700, 0x2b734],
            [0x2b740, 0x2b81d],
            [0x2b820, 0x2cea1],
            [0x2ceb0, 0x2ebe0],

            // [0x2f800, 0x2fa1d],  // DISALLOWED
        ],
    };

    var VIRAMA_LIST = [
        0x94d,
        0x9cd,
        0xa4d,
        0xacd,
        0xb4d,
        0xbcd,
        0xc4d,
        0xccd,
        0xd3b,
        0xd3c,
        0xd4d,
        0xdca,
        0xe3a,
        0xeba,
        0xf84,
        0x1039,
        0x103a,
        0x1714,
        0x1734,
        0x17d2,
        0x1a60,
        0x1b44,
        0x1baa,
        0x1bab,
        0x1bf2,
        0x1bf3,
        0x2d7f,
        0xa806,
        0xa8c4,
        0xa953,
        0xa9c0,
        0xaaf6,
        0xabed,
        0x10a3f,
        0x11046,
        0x1107f,
        0x110b9,
        0x11133,
        0x11134,
        0x111c0,
        0x11235,
        0x112ea,
        0x1134d,
        0x11442,
        0x114c2,
        0x115bf,
        0x1163f,
        0x116b6,
        0x1172b,
        0x11839,
        0x119e0,
        0x11a34,
        0x11a47,
        0x11a99,
        0x11c3f,
        0x11d44,
        0x11d45,
        0x11d97,
    ];

    var SCRIPT_LOOKUP;

    var KATAKANA_MIDDLE_DOT_OK = {
        han: true,
        katakana: true,
        hiragana: true,
    };

    function _getCodePointScript(cp) {
        if (!SCRIPT_LOOKUP) {
            var scriptNames = Object.keys(SCRIPT_DATA);

            SCRIPT_LOOKUP = {};

            scriptNames.forEach( function(script) {
                UNICODE.augmentCodePointLookup(SCRIPT_DATA[script], SCRIPT_LOOKUP, script);
            } );
        }

        return SCRIPT_LOOKUP[cp];
    }

    function _encodeCP(cp) {
        return PUNYCODE.ucs2.encode([cp]);
    }

    function _getContextDefectCPs(label) {
        var badContext = [];

        // Implementations of various parts of
        // https://www.iana.org/assignments/idna-tables-6.3.0/idna-tables-6.3.0.xhtml

        var codePoints = PUNYCODE.ucs2.decode(label);

        CODE_POINT:
        for (var i = 0; i < codePoints.length; i++) {
            var ii;

            switch (codePoints[i]) {

                case 0x200c:

                    // TODO: We have the Virama logic but need the check
                    // on joining type for this to be functional.

                    break;

                case 0x200d:

                    // Previous character’s canonical combining class
                    // must be Virama.
                    if (-1 === VIRAMA_LIST.indexOf(codePoints[i - 1])) {
                        badContext.push(codePoints[i]);
                    }

                    break;

                case 0xb7:
                    if (codePoints[i - 1] !== 0x6c || codePoints[i + 1] !== 0x6c) {
                        badContext.push(codePoints[i]);
                    }

                    break;

                case 0x375:

                    // The script of the following character MUST be Greek.
                    if (_getCodePointScript(codePoints[i + 1]) !== "greek") {
                        badContext.push(codePoints[i]);
                    }
                    break;

                case 0x5f3:
                case 0x5f4:

                    // The script of the preceding character MUST be Hebrew.
                    if (_getCodePointScript(codePoints[i - 1]) !== "hebrew") {
                        badContext.push(codePoints[i]);
                    }
                    break;

                case 0x30fb:

                    // At least one character in the label must be of the
                    // Hiragana, Katakana, or Han script.
                    for (ii = 0; ii < codePoints.length; ii++) {
                        var cpScript = _getCodePointScript(codePoints[ii]);
                        if (KATAKANA_MIDDLE_DOT_OK[cpScript]) {
                            continue CODE_POINT;
                        }
                    }

                    badContext.push(codePoints[i]);
                    break;

                default:

                    // Arabic-Indic digits can’t be with Extended Arabic-Indic
                    if (codePoints[i] >= 0x660 && codePoints[i] <= 0x669) {
                        for (ii = 0; ii < codePoints.length; ii++) {
                            if (codePoints[ii] >= 0x6f0 && codePoints[ii] <= 0x6f9) {
                                badContext.push(codePoints[i]);
                                break;
                            }
                        }
                    }

                    // Extended Arabic-Indic digits can’t be with
                    // (regular) Arabic-Indic
                    if (codePoints[i] >= 0x6f0 && codePoints[i] <= 0x6f9) {
                        for (ii = 0; ii < codePoints.length; ii++) {
                            if (codePoints[ii] >= 0x660 && codePoints[ii] <= 0x669) {
                                badContext.push(codePoints[i]);
                                break;
                            }
                        }
                    }
            }
        }

        return _.uniq(badContext);
    }

    function _codePointsToUplus(cps) {
        return cps.map( function(cp) {
            return "U+" + _.padStart(cp.toString(16).toUpperCase(), 4, "0");
        } );
    }

    /**
    * @function getLabelDefects
    *
    * @param label String The input to parse as an IDN label.
    * @returns Array Human-readable descriptions of the validation errors.
    */
    function getLabelDefects(label) {
        var phrases = [];

        var disallowed = IDN_DISALLOWED.getDisallowedInLabel(label);
        if (disallowed.length) {
            var cps = PUNYCODE.ucs2.decode( disallowed.join("") );
            var upluses = _codePointsToUplus(cps);
            phrases.push( LOCALE.maketext("Domain names may not contain [list_or_quoted,_1] ([list_or,_2]).", disallowed, upluses) );
        }

        var badContextCPs = _getContextDefectCPs(label);
        if (badContextCPs.length) {
            var chars = badContextCPs.map( _encodeCP );
            var ctxUpluses = _codePointsToUplus(badContextCPs);
            phrases.push( LOCALE.maketext("You must use [list_and_quoted,_1] ([list_and,_2]) properly in domain names.", chars, ctxUpluses) );
        }

        if (label.substr(2, 2) === "--") {
            phrases.push( LOCALE.maketext("“[_1]” is forbidden at the third position of a domain label.", "--") );
        }

        if (/^-|-$/.test(label)) {
            phrases.push( LOCALE.maketext("“[_1]” is forbidden at the start or end of a domain label.", "-") );
        }

        return phrases;
    }

    return {
        getLabelDefects: getLabelDefects,

        // for testing only
        _lists: _.assign(
            {},
            SCRIPT_DATA,
            { virama: VIRAMA_LIST }
        ),
    };
});
