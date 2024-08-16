/*
# cpanel - base/frontend/jupiter/zone_editor/services/page_data_service.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "shared/js/zone_editor/models/dynamic_table",
    ],
    function(angular, DynamicTable) {

        "use strict";

        // Fetch the current application
        var app = angular.module("cpanel.zoneEditor");

        /**
         * Setup the domainlist models API service
         */
        app.factory("pageDataService", [ function() {

            return {

                /**
                 * Helper method to remodel the default data passed from the backend
                 * @param  {Object} defaults - Defaults object passed from the backend
                 * @return {Object}
                 */
                prepareDefaultInfo: function(defaults) {
                    defaults.has_adv_feature = defaults.has_adv_feature || false;
                    defaults.has_simple_feature = defaults.has_simple_feature || false;
                    defaults.has_dnssec_feature = defaults.has_dnssec_feature || false;
                    defaults.has_mx_feature = defaults.has_mx_feature || false;
                    defaults.domains = defaults.domains || [];

                    // eslint-disable-next-line camelcase
                    var pageSizeOptions = DynamicTable.PAGE_SIZES;
                    if (typeof defaults.zones_per_page !== "number") {
                        defaults.zones_per_page = parseInt(defaults.zones_per_page, 10);
                    }
                    if (!defaults.zones_per_page || pageSizeOptions.indexOf(defaults.zones_per_page) === -1 ) {
                        defaults.zones_per_page = DynamicTable.DEFAULT_PAGE_SIZE;
                    }

                    if (typeof defaults.domains_per_page !== "number") {
                        defaults.domains_per_page = parseInt(defaults.domains_per_page, 10);
                    }
                    if (!defaults.domains_per_page || pageSizeOptions.indexOf(defaults.domains_per_page) === -1 ) {
                        defaults.domains_per_page = DynamicTable.DEFAULT_PAGE_SIZE;
                    }

                    defaults.isRTL = defaults.isRTL || false;
                    return defaults;
                },

            };
        }]);
    }
);
