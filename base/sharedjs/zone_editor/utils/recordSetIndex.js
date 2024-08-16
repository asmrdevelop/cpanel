/*
# cpanel - base/sharedjs/zone_editor/utils/recordSetIndex.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "shared/js/zone_editor/utils/recordSet",
], function(RecordSet) {
    "use strict";

    function RecordSetIndex() {}
    Object.assign(
        RecordSetIndex.prototype,
        {
            query: function query(name, type) {
                var key = name + ":" + type;

                if (!this[key]) {
                    this[key] = new RecordSet();
                }

                return this[key];
            },

            sets: function sets() {
                return Object.values(this);
            },
        }
    );

    return RecordSetIndex;
});
