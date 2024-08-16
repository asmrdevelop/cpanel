/*
# cpanel - base/sharedjs/zone_editor/utils/dnssec.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "lodash",
], function(_) {
    "use strict";

    var dsAlgorithms = [
        {
            "algorithmId": 1,
            "algorithm": "1-RSAMD5",
        },
        {
            "algorithmId": 2,
            "algorithm": "2-Diffie-Hellman",
        },
        {
            "algorithmId": 3,
            "algorithm": "3-DSA/SHA-1",
        },
        {
            "algorithmId": 4,
            "algorithm": "4-Elliptic Curve",
        },
        {
            "algorithmId": 5,
            "algorithm": "5-RSA/SHA-1",
        },
        {
            "algorithmId": 7,
            "algorithm": "7-RSASHA1-NSEC3-SHA1",
        },
        {
            "algorithmId": 8,
            "algorithm": "8-RSA/SHA-256",
        },
        {
            "algorithmId": 10,
            "algorithm": "10-RSA/SHA-512",
        },
        {
            "algorithmId": 13,
            "algorithm": "13-ECDSA Curve P-256 with SHA-256",
        },
        {
            "algorithmId": 14,
            "algorithm": "14-ECDSA Curve P-384 with SHA-384",
        },
        {
            "algorithmId": 252,
            "algorithm": "252-Indirect",
        },
        {
            "algorithmId": 253,
            "algorithm": "253-Private DNS",
        },
        {
            "algorithmId": 254,
            "algorithm": "254-Private OID",
        },
    ];

    var dsDigTypes = [
        {
            "digTypeId": 1,
            "digType": "1-SHA-1",
        },
        {
            "digTypeId": 2,
            "digType": "2-SHA-256",
        },
        {
            "digTypeId": 4,
            "digType": "4-SHA-384",
        },
    ];

    return {
        dsAlgorithms: dsAlgorithms,
        dsDigTypes: dsDigTypes,
    };
});
