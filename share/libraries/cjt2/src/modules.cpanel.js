/*
# cjt/modules.cpanel.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides the dependencies for cPanel's CJT2 Angular module.
 *
 * @module   cjt/module.cpanel
 */

define(
    [
        "cjt/config/cpanel/configProvider",
        "cjt/directives/cpanel/searchSettingsPanel",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/services/cpanel/SSLStatus",
        "cjt/services/cpanel/notificationsService",
        "cjt/services/cpanel/nvDataService"
    ],
    function() {
        "use strict";

        // Return the Angular modules provided by the dependency files
        return [
            "cjt2.config.cpanel.configProvider",
            "cjt2.directives.cpanel.searchSettingsPanel",
            "cjt2.services.cpanel.componentSettingSaverService",
            "cjt2.services.cpanel.sslStatus",
            "cjt2.services.cpanel.notifications",
            "cjt2.services.cpanel.nvdata"
        ];
    }
);
