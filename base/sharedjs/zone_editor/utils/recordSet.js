/*
# cpanel - base/sharedjs/zone_editor/utils/recordSet.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "lodash",
], function(_) {
    "use strict";

    // cf. DNS_RDATATYPEATTR_SINGLETON in bind9.
    var IS_SINGLETON_TYPE = {
        CNAME: true,

        // DNAME and SOA are also singleton types, but
        // we don’t handle DNAME, and this interface doesn’t
        // expose controls to create additional SOAs.
    };

    function RecordSet() {
        this.records = [];
    }
    Object.assign(
        RecordSet.prototype,
        {
            _ttlsAllMatch: true,

            _ttl: null,

            add: function add(record) {
                record.ttl = parseInt(record.ttl, 10);

                this.records.push(record);

                if (this._ttl) {
                    this._ttlsAllMatch = (this._ttl === record.ttl);
                } else {
                    this._ttl = record.ttl;
                }
            },

            ttlsMismatch: function ttlsMismatch() {
                return !this._ttlsAllMatch;
            },

            singletonExcess: function singletonExcess() {
                return IS_SINGLETON_TYPE[this.records[0].record_type] ? this.records.length > 1 : false;
            },

            ttls: function ttls() {
                return _.uniq(
                    this.records.map(
                        function(r) {
                            return r.ttl;
                        }
                    )
                );
            },

            count: function count() {
                return this.records.length;
            },

            name: function name() {
                return this.records[0].name;
            },

            type: function type() {
                return this.records[0].record_type;
            },
        }
    );

    return RecordSet;
});
