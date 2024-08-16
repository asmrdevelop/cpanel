/*
# cjt/models/searchSettingsModel.js                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides a factory method for generating a searchSettingsPanel
 * directive for a given environment.
 *
 * @module   cjt/directives/searchSettingsModel
 */

/* eslint-disable camelcase */
define(
    [
        "angular",
        "cjt/util/locale",
    ],
    function(angular, LOCALE) {
        "use strict";

        // Retrieve the current application
        var module = angular.module("cjt2.directives.searchSettingsModel", []);


        /**
         * @external ngFilter
         * @see {@link https://docs.angularjs.org/api/ng/filter/filter|$filter}
         */

        /**
          * @typedef {Object} SearchSettingOption
          * @property {String} label        label for the option. Should be localized.
          * @property {String} description  description of the option. Should be localized.
          * @property {String|Number} value value for the option
          */

        /**
          * The SearchSettingsModel consists of one or more of these objects.
          *
          * @typedef {Object} SearchSetting
          * @property {String} label     label for the setting.
          * @property {String} item_key  key to find the item in nvdata.
          * @property {SearchSettingOption[]} options list of options that can be selected
          */

        /**
         * Factory for creating a SearchSettingsModel
         *
         * @ngfactory SearchSettingsModel
         * @param  {ngFilter} $filter     Filter service from angularjs.
         * @return {SearchSettingsModel}  [description]
         */
        module.factory("SearchSettingsModel", ["$filter", function($filter) {

            /**
             *
             * @class SearchSettingsModel
             * @param {Object.<string, SearchSetting>} options set of options to be displayed by the SearchSettingsPanel which would look as follows:
             *
             *  {
             *      optionList2: {
             *          label: "This is the column label of the option",
             *          item_key: "this_is_the_reference_key_to_filter_on",
             *          options: [
             *              {
             *                  value: "value_item_key_must_be_if_this_is_selected",
             *                  label: "Label of the option listed on the panel",
             *                  description: "uib-tooltip description for option"
             *              }
             *              ...
             *          ]
             *      },
             *      ...
             *      optionList2: ...
             *  }
             *
             * @param  {Object.<string, Object>} option_values default values for specific options:
             *
             *  {
             *      uniqueOptionKey: {
             *          "value_item_key_must_be_if_this_is_selected": "default value"
             *          ...
             *      },
             *      ...
             *  }
             *
             * @return {SearchSettingsModel}
             *
             */
            function SearchSettingsModel(options, option_values) {

                var self = this;

                self.settings = null;
                self.settings_values = null;

                // Because option_values is optional
                option_values = option_values || {};

                /**
                 * Uses the originally passed "options" parameter to generate the
                 * initial settings and values.
                 *
                 * @method _initate_values
                 * @private
                 *
                 */
                self._initate_values = function _initate_values() {
                    if (self.settings) {
                        return true;
                    }
                    self.settings = {};
                    self.settings_values = {};
                    angular.forEach(options, function(setting, filterKey) {
                        self.settings[filterKey] = setting;
                        self.settings_values[filterKey] = {};
                        angular.forEach(setting.options, function(option) {
                            if (option_values[filterKey] && !angular.isUndefined(option_values[filterKey][option.value])) {
                                self.settings_values[filterKey][option.value] = option_values[filterKey][option.value];
                            } else {
                                self.settings_values[filterKey][option.value] = true;
                            }
                        });
                    });
                };

            }

            angular.extend(SearchSettingsModel.prototype, {

                /**
                 * Get the parsed settings object
                 *
                 * @method get_settings
                 * @return {Object} current settings object
                 */
                get_settings: function() {
                    this._initate_values();
                    return this.settings;
                },

                /**
                 * Get the current set values of the settings
                 *
                 * @method get_values
                 * @return {Object} Returns the settings values object. The values correlate to the options->value from the original options array.
                 *
                 *  {
                 *      uniqueOptionKey: {
                 *          "value_item_key_must_be_if_this_is_selected":true,
                 *          "value_item_key_must_be_if_this_is_selected2":true,
                 *          "value_item_key_must_be_if_this_is_selected3":true
                 *          ...
                 *      },
                 *      ...
                 *  }
                 *
                 */
                get_values: function() {
                    this._initate_values();
                    return this.settings_values;
                },

                /**
                 * Get a list of values for filtered items for a specific filterType
                 *
                 * @method get_filtered_values
                 * @param  {String} filterType The column for which you want to get the labels (correlates to the original options top level keys)
                 * @return {Array.<Any>} returns a flat array of values from a filterType.
                 *  [true, false, true, true, true]
                 *
                 */
                get_filtered_values: function(filterType) {
                    var self = this;
                    var filterOptions = self.settings[filterType];
                    var values = [];
                    var settings_values = self.get_values();

                    if (!settings_values) {
                        return [];
                    }

                    if (filterOptions) {
                        angular.forEach(filterOptions.options, function(option) {
                            if (settings_values[filterType][option.value]) {
                                values.push(option.value);
                            }
                        });
                    }

                    return values;
                },

                /**
                 * Get a list of display labels for filtered items for a specific filterType
                 *
                 * @method get_filtered_labels
                 * @param  {String} filterType The column for which you want to get the labels (correlates to the original options top level keys)
                 * @return {Array.<String>} returns a flat array of labels to display. If no items are filtered, the array is empty.
                 *  ["Lela", "Fry", "Bender"]
                 */
                get_filtered_labels: function(filterType) {
                    var self = this;
                    var filterOptions = self.settings[filterType];
                    var values = [];
                    var settings_values = self.get_values();

                    if (!settings_values) {
                        return [];
                    }

                    if (filterOptions) {
                        angular.forEach(filterOptions.options, function(option) {
                            if (settings_values[filterType][option.value]) {
                                values.push(option.label);
                            }
                        });

                        // so that we don't display the label if we're showing "all", but we don't have to relay on in-dom logic
                        if (values.length === filterOptions.options.length) {
                            return [];
                        }
                    }

                    return values.length ? values : [LOCALE.maketext("None")];
                },

                /**
                 * Set all the items in a column to a value
                 *
                 * @method set_search_filter_values
                 * @param  {String} filterKey The column for which you want to update the values (correlates to the original options top level keys)
                 * @param  {*} filterValue new value to set the items to
                 * @return {None} does not return a value
                 */
                set_search_filter_values: function(filterKey, filterValue) {
                    var self = this;
                    angular.forEach(self.settings_values[filterKey], function(option, key) {
                        self.settings_values[filterKey][key] = filterValue;
                    });
                },

                /**
                 * Isolate a specific item in a filter to display only that one
                 *
                 * @method show_only
                 * @param  {String} filterKey key associated with the column
                 * @param  {String} itemKey key associated with the row in the column
                 * @return {None} None
                 */
                show_only: function(filterKey, itemKey) {
                    var self = this;

                    self.set_search_filter_values(filterKey, false);
                    if (self.settings_values[filterKey]) {
                        self.settings_values[filterKey][itemKey] = true;
                    }
                },

                /**
                 * This is the hook function used to filter the items list. It will use the existing setting_values and compare them to the item value key
                 *
                 * @method filter
                 * @param  {Array} items An array of items to filter based on each of the options in the panel
                 *
                 *  [
                 *      {
                 *          key: value, // where 'key' correlates the the 'item_key' established by each column in the initial options array
                 *          key2: value
                 *      }
                 *  ]
                 *
                 * @return {Array} filtered version of the passed in items array
                 *
                 */
                filter: function(items) {

                    var typesToFilter = {};
                    var self = this;

                    angular.forEach(self.settings, function(searchFilterOption, filterKey) {
                        var true_values = [];
                        angular.forEach(searchFilterOption.options, function(option) {

                            // One of the options isn't selected; filter based on it
                            if (self.settings_values[filterKey][option.value]) {
                                true_values.push(option.value);
                            }
                        });

                        // lengths are not equal; some are disabled.
                        if (true_values.length !== searchFilterOption.options.length) {

                            // store in keyed values for faster lookup
                            typesToFilter[filterKey] = {};
                            angular.forEach(true_values, function(true_value) {
                                typesToFilter[filterKey][true_value] = 1;
                            });
                        }
                    });

                    return $filter("filter")(items, function(item) {

                        for (var settingKey in typesToFilter) {
                            if (typesToFilter.hasOwnProperty(settingKey)) {
                                var itemKey = self.settings[settingKey].item_key;
                                var itemValue = item[itemKey];

                                // value doesn't exist in the allowed and filtered values
                                if (!self.settings_values[settingKey][itemValue]) {
                                    return false;
                                }
                            }
                        }

                        return true;
                    });
                }
            });

            return SearchSettingsModel;

        }]);
    }
);
