/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/customizeService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* jshint -W089 */
/* jshint -W018 */

define(
    [

        // Libraries
        "angular",
        "cjt/util/locale",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "app/constants",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        "cjt/services/APICatcher",
    ],
    function(angular, LOCALE, API, APIREQUEST, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.services.customizeService", [
            "cjt2.services.apicatcher",
            "cjt2.services.api",
        ]);

        module.factory("customizeService", ["APICatcher", "$q", function(APICatcher, $q) {

            // return the factory interface
            return {

                /**
                 * @typedef CustomizationModel
                 * @property {Object} brand - properties related to branding a cPanel instanance.
                 * @property {Object} brand.logo - properties related to the logos used in the UI.
                 * @property {string} brand.logo.forLightBackground - base64 encoded logo used when the background color is light.
                 * @property {string} brand.logo.forDarkBackground - base64 encoded logo used when the background color is dark.
                 * @property {string} brand.logo.description - title used with the logo for assistive technology
                 * @property {Object} brand.colors - dictionary of customizable colors for the UI.
                 * @property {string} brand.colors.primary - hex color used in primary UI features.
                 * @property {string} brand.colors.link - hex color used in links.
                 * @property {string} brand.colors.accent - hex color used in accents.
                 * @property {string} brand.favicon - base64 encoded favicon.
                 * @property {Object} help - online help related properties.
                 * @property {string} help.url - URL to the online help for a company.
                 * @property {Object} documentation - documenation related properties.
                 * @property {string} documentation.url - URL to the custom documentation site for a company.
                 */

                /**
                 * Update the customization options for jupiter based themes
                 *
                 * @async
                 * @param {CustomizationModel} customizations - the updated customizations to store on the server.
                 * @param {string} theme - the theme name to which the customization is updated. Defaults to CONSTANTS.DEFAULT_THEME.
                 */
                update: function(customizations, theme) {
                    if (angular.isUndefined(customizations)) {
                        return $q.reject(LOCALE.maketext("The customization parameter is missing or not an object."));
                    }

                    var apicall = new APIREQUEST.Class().initialize(
                        "", "update_customizations", {
                            application: "cpanel",
                            theme: theme || CONSTANTS.DEFAULT_THEME,
                            data: JSON.stringify(customizations),
                        });

                    return APICatcher.promise(apicall);
                },

                /**
                 * Delete a path in the the customization data.
                 *
                 * @async
                 * @param {string} path - optional, The JSONPath to delete
                 * @param {string} theme - the theme name to which the customization is updated. Defaults to CONSTANTS.DEFAULT_THEME.
                 */
                delete: function(path, theme) {
                    var apicall = new APIREQUEST.Class().initialize(
                        "", "delete_customizations", {
                            application: "cpanel",
                            theme: theme || CONSTANTS.DEFAULT_THEME,
                            path: path,
                        });

                    return APICatcher.promise(apicall);
                },

                /**
                 * For the provided tabInfo, this method retrieves the tabs list and their associcated information.
                 *
                 * @param {Object} tabInfo - The theme specific tab information.
                 */
                getThemeTabList: function(tabInfo) {
                    var themeTabs = tabInfo.order.map(tab => {
                        return {
                            key: tab, name: CONSTANTS.GENERAL_TABS_INFO[tab], index: tabInfo.index[tab],
                        };
                    });
                    return themeTabs;
                },
            };
        }]);
    }
);
