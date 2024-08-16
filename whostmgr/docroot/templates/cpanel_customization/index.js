/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

(function() {
    "use strict";

    define(
        [
            "lodash",
            "angular",
            "cjt/core",
            "cjt/util/locale",
            "app/constants",
            "cjt/modules",
            "uiBootstrap",
            "cjt/directives/callout",
            "app/services/savedService",
            "app/services/beforeUnloadService",

            // Jupiter Views
            "app/views/jupiter/logoController",
            "app/views/jupiter/faviconController",
            "app/views/jupiter/linksController",
            "app/views/jupiter/colorsController",

            // Shared Views
            "app/views/publicContactController",
        ],
        function(_, angular, CJT, LOCALE, CONSTANTS) {
            return function() {
                angular.module("App", [
                    "cjt2.config.whm.configProvider", // This needs to load first
                    "ngRoute",
                    "ui.bootstrap",
                    "angular-growl",
                    "cjt2.whm",
                    "customize.services.savedService",
                    "customize.services.beforeUnloadService",

                    // Jupiter
                    "customize.views.logoController",
                    "customize.views.faviconController",
                    "customize.views.linksController",
                    "customize.views.colorsController",

                    // Shared
                    "customize.views.publicContactController",
                ]);

                var app = require(
                    [
                        "cjt/bootstrap",

                        // Application Modules
                        "uiBootstrap",

                        // Jupiter Views
                        "app/views/jupiter/logoController",
                        "app/views/jupiter/faviconController",
                        "app/views/jupiter/linksController",
                        "app/views/jupiter/colorsController",

                        // Shared Views
                        "app/views/publicContactController",

                        // Services
                        "app/services/contactService",
                        "app/services/customizeService",
                    ], function(BOOTSTRAP) {

                        var app = angular.module("App");
                        app.value("PAGE", PAGE);

                        app.value("firstLoad", {
                            branding: true,
                        });

                        app.controller("BaseController", [
                            "$rootScope",
                            "$scope",
                            "$route",
                            "$location",
                            "growl",
                            "growlMessages",
                            "$timeout",
                            "savedService",
                            "customizeService",
                            function($rootScope, $scope, $route, $location, growl, growlMessages, $timeout, savedService, customizeService) {
                                CONSTANTS.DEFAULT_THEME = PAGE.data.default_theme;
                                $scope.loading = false;
                                $scope.selectedThemeTabList = [];
                                savedService.registerTabs(CONSTANTS.JUPITER_TAB_ORDER);

                                // Convenience functions so we can track changing views for loading purposes
                                $rootScope.$on("$routeChangeStart", function() {
                                    if (savedService.needToSave()) {
                                        $scope.reportNotSaved();
                                        event.preventDefault();
                                    }

                                    $scope.loading = true;
                                });

                                $rootScope.$on("$routeChangeSuccess", function() {
                                    $scope.loading = false;
                                });

                                $rootScope.$on("$routeChangeError", function() {
                                    $scope.loading = false;
                                });

                                $rootScope.$on("onBeforeUnload", function(e, config) {
                                    if (savedService.needToSave()) {
                                        config.prompt = LOCALE.maketext("The current tab has unsaved changes. You should save the changes before you navigate to another tab.");
                                        e.preventDefault();

                                        return;
                                    }
                                    delete e["returnValue"];
                                });

                                /**
                                 * Select a tab by its key. See the indexes for each tab in the ./index.html.tt file.
                                 *
                                 * @param {number} index
                                 */
                                $scope.selectTab = function(index) {
                                    var tabInfo = getTabInfo();
                                    tabInfo.lastTab = index;
                                    var activeIndex = tabInfo.index[index];
                                    $scope.activeTab = activeIndex;
                                };

                                /**
                                 * Navigate to the selected path and change the tab being viewed.
                                 *
                                 * @param {string} path
                                 */
                                $scope.goTo = function(path) {
                                    var tabInfo = getTabInfo();
                                    tabInfo.lastTab = path;
                                    $scope.selectTab(path);
                                    $location.path(path);
                                    $scope.selectTab(path);
                                    $scope.currentTabName = path;
                                };

                                /**
                                 * Growl a message about not changing tabs.
                                 */
                                $scope.reportNotSaved = function() {
                                    growlMessages.destroyAllMessages();
                                    growl.error(LOCALE.maketext("The current tab has unsaved changes. You should save the changes before you navigate to another tab."));
                                };

                                /**
                                 * Do not let the user navigate away from a tab if there
                                 * is unsaved work.
                                 */
                                $scope.preventDeselect = function($event) {
                                    if (!$event || !$event.target) {
                                        return;
                                    }

                                    var tabName = findTabName(angular.element($event.target));
                                    if (savedService.needToSave($scope.currentTabName)) {
                                        if (tabName !== $scope.currentTabName) {
                                            $scope.reportNotSaved();
                                        }
                                        $event.preventDefault();
                                    }
                                    return;
                                };

                                /**
                                 * Dig thru the els to find the parent with the data-tab-name attribute
                                 *
                                 * @private
                                 * @param {JqLiteHtmlElement} el
                                 * @returns {string}
                                 */
                                function findTabName(el) {
                                    var name = el.attr("data-tab-name");
                                    if (name) {
                                        return name;
                                    }
                                    var parent = el.parent();
                                    if (parent) {
                                        return findTabName(parent);
                                    }
                                    return;
                                }

                                /**
                                 * @typedef ThemeInfo - a set of properties used to configure the tabs for a given theme.
                                 * @property {string[]} order - the list of tab names in the order they are shown.
                                 * @property {Dictionayr<string,number>} index - the lookup table of tab names to tab indexes.
                                 * @property {string} lastTab - the previously selected tab.
                                 */
                                /**
                                 * @typedef ThemesInfo - lookup table of tab configuration per theme.
                                 * @property {ThemeInfo} jupiter - the jupiter theme configuraiton
                                 */

                                /**
                                 * @name byTheme
                                 * @scope
                                 * @type {ThemesInfo}
                                 */
                                $scope.byTheme = {
                                    jupiter: {
                                        order: CONSTANTS.JUPITER_TAB_ORDER,
                                        index: CONSTANTS.JUPITER_TAB_INDEX,
                                        lastTab: "",
                                    },
                                };

                                $scope.selectedTheme = CONSTANTS.DEFAULT_THEME;

                                /**
                                 * Handle theme changes.
                                 */
                                $scope.onThemeSelect = function() {
                                    initTab();
                                };

                                /**
                                 * Retrieve the tab information for the current selected theme.
                                 *
                                 * @returns {ThemeInfo}
                                 */
                                function getTabInfo() {
                                    return $scope.byTheme[$scope.selectedTheme];
                                }

                                /**
                                 * Check if the theme matches the current theme.
                                 *
                                 * @param {string} themeName
                                 * @returns {boolean} true when they are the same, false otherwise.
                                 */
                                $scope.isTheme = function(themeName) {
                                    return $scope.selectedTheme === themeName;
                                };

                                /**
                                 * Check if the tab with the tabName is the active tab.
                                 *
                                 * @param {String} tabName
                                 * @returns {boolean} true when the tab is active, false otherwise.
                                 */
                                $scope.isActive = function(tabName) {
                                    return $scope.activeTab === tabName;
                                };

                                /**
                                 * Get the active tab name.
                                 *
                                 * @returns {string} The name of the active tab.
                                 */
                                $scope.getActiveTab = function() {
                                    return $scope.activeTab;
                                };

                                /**
                                 * The name of the currently selected tab
                                 * @type {string}
                                 */
                                $scope.currentTabName = "";

                                /**
                                 * Select the initial tab.
                                 */
                                function initTab() {
                                    var tabInfo = getTabInfo();
                                    $scope.selectedThemeTabList = customizeService.getThemeTabList(tabInfo);
                                    var tabName = tabInfo.lastTab || tabInfo.order[0];

                                    $timeout(function() {
                                        $scope.goTo(tabName);
                                    });
                                }

                                initTab();
                            },
                        ]);

                        app.config(["$routeProvider",
                            function($routeProvider) {

                                // Setup a route - copy this to add additional routes as necessary
                                $routeProvider.when("/logos", {
                                    controller: "logoController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/logo.ptt"),
                                });

                                $routeProvider.when("/colors", {
                                    controller: "colorsController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/colors.ptt"),
                                });

                                $routeProvider.when("/links", {
                                    controller: "linksController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/links.ptt"),
                                });

                                $routeProvider.when("/favicon", {
                                    controller: "faviconController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/favicon.ptt"),
                                });

                                $routeProvider.when("/public-contact", {
                                    controller: "publicContactController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/publicContact.ptt"),
                                });

                                // default route
                                $routeProvider.otherwise({
                                    "redirectTo": "/" + CONSTANTS.DEFAULT_ROUTE,
                                });
                            },
                        ]);

                        // Initialize the application
                        BOOTSTRAP();

                    });

                return app;
            };
        }
    );

})();
