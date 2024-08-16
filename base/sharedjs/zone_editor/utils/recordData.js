/*
# cpanel - base/sharedjs/zone_editor/utils/recordData.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "lodash",
    "shared/js/zone_editor/utils/dnssec",
], function(_, DNSSEC) {
    "use strict";

    // Keys are record types; values are arrays of 2-member arrays;
    // each 2-member array is the record-object key and its default.
    //
    // Note the following “special” defaults:
    //  - If the default is a function, the function’s result will be
    //      the default.
    //  - If the default is undefined, the key will be omitted from
    //      the default data.
    //
    var TYPE_FIELDS_WITH_DEFAULTS = {
        A: [
            { key: "a_address", default: "" },
        ],

        AAAA: [
            { key: "aaaa_address", default: "" },
        ],

        AFSDB: [
            { key: "subtype", default: null },
            { key: "hostname", default: "" },
        ],

        CAA: [
            { key: "flag", default: 0 },
            { key: "tag", default: "issue" },
            { key: "value", default: "" },
        ],

        CNAME: [
            { key: "cname", default: "" },
        ],

        DNAME: [
            { key: "dname", default: "" },
        ],

        DS: [
            { key: "keytag", default: "" },
            { key: "algorithm", default: DNSSEC.dsAlgorithms[0].algorithm },
            { key: "digtype", default: DNSSEC.dsDigTypes[0].digType },
            { key: "digest", default: "" },
        ],

        HINFO: [
            { key: "cpu", default: "" },
            { key: "os", default: "" },
        ],

        LOC: [
            { key: "latitude", default: "" },
            { key: "longitude", default: "" },
            { key: "altitude", default: null },
            { key: "size", default: "1" },
            { key: "horiz_pre", default: "1000" },
            { key: "vert_pre", default: "10" },
        ],

        MX: [
            { key: "priority", default: null },
            { key: "exchange", default: undefined },
        ],

        NS: [
            { key: "nsdname", default: "" },
        ],

        NAPTR: [
            { key: "order", default: null },
            { key: "preference", default: null },
            { key: "flags", default: null },
            { key: "service", default: "" },
            { key: "regexp", default: "" },
            { key: "replacement", default: "" },
        ],

        PTR: [
            { key: "ptrdname", default: "" },
        ],

        RP: [
            { key: "mbox", default: "" },
            { key: "txtdname", default: "" },
        ],

        SOA: [
            { key: "serial", default: "" },
            { key: "mname", default: "" },
            { key: "retry", default: null },
            { key: "refresh", default: null },
            { key: "expire", default: null },
            { key: "rname", default: "" },
        ],

        SRV: [
            { key: "priority", default: null },
            { key: "weight", default: null },
            { key: "port", default: null },
            { key: "target", default: "" },
        ],

        TXT: [
            { key: "txtdata", default: function() {
                return [];
            } },
        ],
    };

    function createNewDefaultData() {
        var data = {};

        Object.values(TYPE_FIELDS_WITH_DEFAULTS).forEach( function(fields) {
            fields.forEach( function(field) {
                var rawValue = field.default;

                var realValue;

                if (typeof rawValue === "function") {
                    realValue = rawValue();
                } else if (typeof rawValue === "undefined") {
                    return;
                } else {
                    realValue = rawValue;
                }

                data[ field.key ] = realValue;
            } );
        } );

        return data;
    }

    var TYPE_SEARCH = {};

    Object.keys(TYPE_FIELDS_WITH_DEFAULTS).forEach( function(type) {
        var keys = TYPE_FIELDS_WITH_DEFAULTS[type].map(
            function(keyValue) {
                return keyValue.key;
            }
        );

        var keysCount = keys.length;

        TYPE_SEARCH[type] = function(record, sought) {
            for (var k = 0; k < keysCount; k++) {
                var fieldValue = record[ keys[k] ];

                if (fieldValue === null || fieldValue === undefined) {
                    continue;
                }

                if (-1 !== fieldValue.toString().indexOf(sought)) {
                    return true;
                }
            }

            return false;
        };
    } );

    // A special snowflake:
    TYPE_SEARCH.TXT = function(record, sought) {

        // Each TXT record is an array of strings. While not all protocols
        // define a join mechanism for those strings, it’s commonplace to
        // concatenate them together. (e.g., DKIM and SPF) Since this is
        // both common and also kind of a “default”, simplest model,
        // let’s apply it here.
        //
        var txtdata = record.txtdata.join("");

        if (-1 !== txtdata.indexOf(sought)) {
            return true;
        }

        return false;
    };

    return {
        createNewDefaultData: createNewDefaultData,
        searchByType: TYPE_SEARCH,
    };
});
