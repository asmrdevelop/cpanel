/*
 * cjt2/src/directives/whm/searchSettingsPanel.js     Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * Provides searchSettingsPanel for whostmgr. The service saves
 * page specific data by component. Each component is commonly a view.
 *
 * @module   cjt/directives/whm/searchSettingsPanel
 * @ngmodule cjt2.directives.whm.searchSettingsPanel
 */

/* global define: false */
define(
    [
        "cjt/directives/searchSettingsPanelFactory",
        "cjt/services/whm/componentSettingSaverService",
    ],
    function(makeDirective) {
        "use strict";

        /**
         * @ngDirective componentSettingSaverService
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.ngModel as SearchSettingsPanel.ngModel
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.id as SearchSettingsPanel.id
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.ngChange as SearchSettingsPanel.ngChange
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.showCount as SearchSettingsPanel.showCount
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.displaySetValues as SearchSettingsPanel.displaySetValues
         * @borrows module:cjt/directives/searchSettingsPanelFactory/SearchSettingsPanel.displaySettingsPanel as SearchSettingsPanel.displaySettingsPanel
         */
        return makeDirective(
            "cjt2.directives.whm.searchSettingsPanel",
            [
                "cjt2.services.whm.componentSettingSaverService",
                "cjt2.directives.searchSettingsModel",
                "cjt2.templates"
            ]
        );
    }
);
