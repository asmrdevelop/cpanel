/*
# cjt/modules.webmail.js                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides the dependencies for Webmail's CJT2 Angular module.
 *
 * Note that webmail support both api2 and uapi so any services, directive,
 * or other modules that work in cpanel will also work in webmail if the
 * specific apis are granted webmail permissions.
 *
 * @module   cjt/module.webmail
 */

define(
    [
        "cjt/config/webmail/configProvider",
        "cjt/directives/cpanel/searchSettingsPanel",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/services/cpanel/nvDataService",
    ],
    function() {
        "use strict";

        // Return the Angular modules provided by the dependency files
        return [
            "cjt2.config.webmail.configProvider",
            "cjt2.directives.cpanel.searchSettingsPanel",
            "cjt2.services.cpanel.componentSettingSaverService",
            "cjt2.services.cpanel.nvdata",
        ];
    }
);
