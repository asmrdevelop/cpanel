/*
# cjt/modules.whm.js                                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides the dependencies for WHM's CJT2 Angular module.
 *
 * @module   cjt/module.whm
 */

define(
    [
        "cjt/config/whm/configProvider",
        "cjt/directives/whm/searchSettingsPanel",
        "cjt/directives/whm/userDomainListDirective",
        "cjt/io/whm-v1-querystring-service",
        "cjt/services/whm/breadcrumbService",
        "cjt/services/whm/componentSettingSaverService",
        "cjt/services/whm/nvDataService",
        "cjt/services/whm/oauth2Service",
        "cjt/services/whm/titleService",
        "cjt/services/whm/userDomainListService",
    ],
    function() {
        "use strict";

        // Return the Angular modules provided by the dependency files
        return [
            "cjt2.config.whm.configProvider",
            "cjt2.directives.whm.searchSettingsPanel",
            "cjt2.directives.whm.userDomainListDirective",
            "cjt2.services.whm.query",
            "cjt2.services.whm.breadcrumb",
            "cjt2.services.whm.componentSettingSaverService",
            "cjt2.services.whm.nvdata",
            "cjt2.services.whm.oauth2",
            "cjt2.services.whm.title",
            "cjt2.services.whm.userDomainListService",
        ];
    }
);
