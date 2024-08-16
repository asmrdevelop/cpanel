/*
 * cjt2/src/services/cpanel/componentSettingSaverService.js
 *                                                    Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * Provides componentSettingSaverService for cPanel. The service saves
 * page specific data by component. Each component is commonly a view.
 *
 * @module   cjt/services/cpanel/componentSettingSaverService
 * @ngmodule cjt2.services.cpanel.componentSettingSaverService
 */

define(
    [
        "cjt/services/componentSettingSaverFactory",
        "cjt/services/cpanel/nvDataService",
    ],
    function(makeService) {
        "use strict";

        /**
         * @ngService componentSettingSaverService
         * @borrows module:cjt/services/componentSettingSaverFactory.getPageIdentifier as getPageIdentifier
         * @borrows module:cjt/services/componentSettingSaverFactory.register as register
         * @borrows module:cjt/services/componentSettingSaverFactory.unregister as unregister
         * @borrows module:cjt/services/componentSettingSaverFactory.set as set
         * @borrows module:cjt/services/componentSettingSaverFactory.get as get
         */

        return makeService(
            "cjt2.services.cpanel.componentSettingSaverService",
            [
                "cjt2.services.cpanel.nvdata",
                "cjt2.services.pageIdentiferService"
            ]
        );
    }
);
