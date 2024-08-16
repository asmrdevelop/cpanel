/*
# cpanel - whostmgr/docroot/templates/zone_editor/services/page_data_service.js
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
        var MODULE_NAMESPACE = "whm.zoneEditor.services.pageDataService";
        var SERVICE_NAME = "pageDataService";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function() {

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
                    defaults.otherRecordsInterface = defaults.otherRecordsInterface || false;

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
        };

        /**
         * Setup the domainlist models API service
         */
        app.factory(SERVICE_NAME, [ SERVICE_FACTORY ]);

        return {
            class: SERVICE_FACTORY,
            serviceName: SERVICE_NAME,
            namespace: MODULE_NAMESPACE,
        };
    }
);
