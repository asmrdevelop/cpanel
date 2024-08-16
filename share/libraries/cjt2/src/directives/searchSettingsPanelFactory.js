/*
# cjt/directives/searchSettingsPanelFactory.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides a factory method for generating a searchSettingsPanel
 * directive for a given environment.
 *
 * @module   cjt/directives/searchSettingPanelFactory
 */

/* eslint-disable camelcase */
define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "ngSanitize",
        "cjt/models/searchSettingsModel"
    ],
    function(angular, CJT, LOCALE) {
        "use strict";

        /**
         * Generates a searchSettingPanel directive for the given environment
         *
         * @method makeDirective
         * @param  {String}         moduleName         Name of the angular module.
         * @param  {Array.<String>} moduleDependencies List of dependencies for the angular module.
         */
        return function makeDirective(moduleName, moduleDependencies) {

            // Retrieve the current application
            var module = angular.module(moduleName, moduleDependencies);

            var RELATIVE_PATH = "libraries/cjt2/directives/";
            var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;
            var TEMPLATE = TEMPLATES_PATH + "searchSettingsPanel.phtml";

            /**
             * Function that is called when the user changes one of the settings.
             *
             * @callback ngChangeCallback
             */

            /**
             * Creates a panel used with advanced search options.
             * @class SearchSettingsPanel
             * @ngdirective searchSettingsPanel
             */
            module.directive("searchSettingsPanel", ["componentSettingSaverService",
                function($CSSS) {
                    return {
                        templateUrl: TEMPLATE,
                        restrict: "EA",
                        transclude: true,
                        scope: {

                            /**
                             * Collection of configuration settings for filling
                             * in the UI of the panel.
                             * @property ngModel
                             * @ngattr
                             * @type {SearchSettingsModel}
                             */
                            ngModel: "=",

                            /**
                             * Parent element id.
                             *
                             * @property id
                             * @ngattr
                             * @type {String}
                             */
                            parentID: "@id",

                            /**
                             * Called when the user changes one of the settings
                             *
                             * @property ngChange
                             * @ngattr
                             * @type {ngChangeCallback}
                             */
                            ngChange: "&",

                            /**
                             * Determines whether or not the total number of items is shown.
                             *
                             * @property showCount
                             * @ngattr
                             * @type {Boolean}
                             */
                            showCount: "=?",

                            /**
                             * Determines whether or not to show labels under the search bar
                             * corresponding to the filtering options chosen in the settings
                             * panel.
                             *
                             * @property displaySetValues
                             * @ngattr
                             * @type {Boolean}
                             */
                            displaySetValues: "=",

                            /**
                             * Determines whether or not the settings panel is open/shown.
                             *
                             * @property displaySettingsPanel
                             * @ngattr
                             * @type {Boolean}
                             */
                            displaySettingsPanel: "="
                        },
                        link: function(scope) {

                            scope.options = scope.ngModel.get_settings();
                            scope.values = scope.ngModel.get_values();
                            scope.filteredItemsToDisplay = false;
                            scope.searchSettingsID = scope.parentID + "_SearchSettingsPanel";
                            scope.setValuesID = scope.parentID + "_SetValuePanel";
                            scope.all_label = LOCALE.maketext("All");
                            scope.all_checked = {};

                            /**
                             * Set all the items in a column to a value
                             *
                             * @method set_search_filter_values
                             * @scope
                             * @param  {String} filterKey The key for which you want to update the values.
                             * @param  {*} filterValue new value to set the items to
                             */
                            scope.set_search_filter_values = function(filterKey, filterValue) {
                                scope.ngModel.set_search_filter_values(filterKey, filterValue);
                                scope.update();
                            };

                            /**
                             * Builds the list of displayable filtered items
                             *
                             * @method update_display_values
                             * @scope
                             */
                            scope.update_display_values = function() {
                                var showItems = false;
                                angular.forEach(scope.options, function(optionSettings, optionKey) {
                                    scope.all_checked[optionKey] = false;
                                    if (scope.get_filtered_labels(optionKey).length) {
                                        showItems = true;
                                    }
                                    if (scope.get_filtered_values(optionKey).length === optionSettings.options.length) {
                                        scope.all_checked[optionKey] = true;
                                    }
                                });
                                scope.filteredItemsToDisplay = showItems;
                            };

                            /**
                             * Force open the display settings panel
                             *
                             * @method open_settings
                             * @scope
                             */
                            scope.open_settings = function() {
                                scope.displaySettingsPanel = true;
                            };

                            /**
                             * Initiate an NVData save of the current state of the settings panel
                             *
                             * @method saveSettings
                             * @scope
                             */
                            scope.saveSettings = function() {
                                $CSSS.set(scope.parentID, scope.values);
                            };

                            /**
                             * Update display values, save settings, and dispatch an ngChange event
                             *
                             * @method update
                             * @scope
                             */
                            scope.update = function() {
                                scope.update_display_values();
                                scope.saveSettings();
                                scope.ngChange();
                            };

                            /**
                             * Update the display labels with the item counts
                             *
                             * @method update_display_labels
                             * @scope
                             */
                            scope.update_display_labels = function() {

                                scope.all_label = scope.all_label + " (" + scope.showCount.length + ")";

                                var searchable_items = scope.showCount;
                                var search_setting_values = {};

                                /*
                                    translating this:
                                    domainType: {
                                        label: LOCALE.maketext("Domain Types:"),
                                        item_key: "type",
                                        options: [{
                                            "value": "main_domain",
                                            "label": LOCALE.maketext("Main"),
                                            "description": LOCALE.maketext("Only list Main domains.")
                                        }

                                    into this:

                                    search_setting_values["domainType"]["main_domain"] = 0;
                                */


                                // This is split up into three separate loops to allow faster processing and fewer nested loops
                                angular.forEach(scope.options, function(search_option, property_key) {
                                    search_setting_values[property_key] = {};

                                    angular.forEach(search_option.options, function(type) {
                                        var property_value = type.value;

                                        // set count of each value to zero for each property item
                                        search_setting_values[property_key][property_value] = 0;
                                    });

                                });

                                angular.forEach(searchable_items, function(searchable_item) {
                                    angular.forEach(search_setting_values, function(option_value, key) {

                                        var lookup_key = scope.options[key].item_key;

                                        var searchable_item_value = searchable_item[lookup_key];
                                        search_setting_values[key][searchable_item_value]++;

                                    });
                                });

                                angular.forEach(scope.options, function(search_option, property_key) {
                                    angular.forEach(search_option.options, function(type) {
                                        var property_value = type.value;
                                        if (!type.original_label) {
                                            type.original_label = type.label;
                                        }

                                        // set count of each value to zero for each property item
                                        var count = search_setting_values[property_key][property_value];
                                        type.label = type.original_label + " (" + count + ")";
                                    });

                                });

                            };

                            if (scope.showCount && typeof (scope.showCount) === "object") {
                                scope.update_display_labels();

                                scope.$watch("showCount", function() {

                                    // Only updated it if it's being displayed
                                    if (scope.displaySettingsPanel) {
                                        scope.update_display_labels();
                                    }
                                }, true);

                                scope.$watch("displaySettingsPanel", function(newVal, oldVal) {
                                    if (newVal && newVal !== oldVal) {
                                        scope.update_display_labels();
                                    }
                                });
                            }

                            scope.get_filtered_labels = scope.ngModel.get_filtered_labels.bind(scope.ngModel);
                            scope.get_filtered_values = scope.ngModel.get_filtered_values.bind(scope.ngModel);

                            var registering = $CSSS.register(scope.parentID);
                            if (registering) {
                                registering.then(function(result) {
                                    angular.forEach(result, function(filterGroup, filterKey) {

                                        // Filter Key doesn't exist (column no longer exists)
                                        if (!scope.options[filterKey]) {
                                            return;
                                        }

                                        angular.forEach(filterGroup, function(filterItemValue, filterItemKey) {

                                            // Filter Item Key doesn't exist (group item no longer exists)
                                            if (angular.isUndefined(scope.values[filterKey][filterItemKey])) {
                                                return;
                                            }

                                            scope.values[filterKey][filterItemKey] = filterItemValue;

                                        });
                                    });
                                    scope.update_display_values();
                                    scope.ngChange();

                                    // add watch after registration to prevent overwriting data before stored data is loaded
                                    scope.$watch(function() {
                                        return scope.values;
                                    }, function() {
                                        scope.update();
                                    }, true);
                                });
                            }

                            scope.$on("$destroy", function() {
                                $CSSS.unregister(scope.parentID);
                            });
                        },
                    };
                }
            ]);
        };
    }
);
/* eslint-enable camelcase */
