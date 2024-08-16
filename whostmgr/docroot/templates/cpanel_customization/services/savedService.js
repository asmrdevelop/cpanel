/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/savedService.js
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
    ],
    function(angular, API, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("customize.services.savedService", []);

        app.factory("savedService", [function() {
            var tabs = {};

            var DEFAULT = {
                dirty: false,
            };

            // return the factory interface
            return {

                /**
                 * Register all the participating tabs
                 *
                 * @param {string[]} tabNames
                 */
                registerTabs: function(tabNames) {
                    tabNames.forEach(function(tabName) {
                        tabs[tabName] = angular.copy(DEFAULT);
                    });
                },

                /**
                 * Check if the tab or tabs need to be saved. If you provide a `tabName` it
                 * only looks at the one tab, if not it checks all the registered tabs.
                 *
                 * NOTE: Not all tabs are registered currently. Unregisted tabs return false
                 * since they are not yet participating in this system.
                 *
                 * @param {string} tabName
                 * @returns {boolean} true if you need to save something, false otherwise.
                 */
                needToSave: function(tabName) {
                    if (!tabName) {

                        // Check all the tabs
                        return Object.keys(tabs).some(function(tabName) {
                            return tabs[tabName] ? tabs[tabName].dirty : false;
                        });
                    } else {

                        // Check just the requested tab
                        return tabs[tabName] ? tabs[tabName].dirty : false;
                    }
                },

                /**
                 * Mark a tab state:
                 *
                 *   * dirty = true, need to save it.
                 *   * dirty = false, its saved already.
                 *
                 * @param {string} tabName
                 * @param {boolean} dirty
                 */
                update: function(tabName, dirty) {
                    if (tabs[tabName]) {
                        tabs[tabName].dirty = dirty;
                    }
                },
            };
        }]);
    });
