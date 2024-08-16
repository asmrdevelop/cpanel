/*
# countryCodesTableDirective.js                      Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/countriesService",
        "uiBootstrap",
        "cjt/modules",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/spinnerDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/quickFiltersDirective",
        "cjt/directives/toggleSwitchDirective",
    ], function(angular, _, LOCALE, CountriesService) {
        "use strict";

        var TEMPLATE_PATH = "directives/countryCodesTable.ptt";
        var DIRECTIVE_NAME = "countryCodesTable";
        var MODULE_NAMESPACE = "whm.eximBlockCountries.directives.countryCodesTable";
        var MODULE_REQUIREMENTS = [
            "cjt2.services.alert",
            "cjt2.directives.spinner",
            CountriesService.namespace
        ];

        var COUNTRIES_MESSAGE_MAX = 10;
        var CONTROLLER_INJECTABLES = ["$scope", "$filter", CountriesService.serviceName, "alertService"];

        /**
         *
         * Directive Controller for Countries list
         *
         * @module countryCodesTableDirective
         * @memberof whm.eximBlockCountries
         *
         * @param {Object} $scope angular scope instance
         * @param {Object} $filter angular filter instance
         * @param {Object} CountriesService instance
         */
        var CONTROLLER = function($scope, $filter, $service, $alertService) {

            // have your filters all in one place - easy to use
            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy")
            };

            var countriesMap = {};
            var items = $scope.items ? $scope.items : [];
            items.forEach(function(item) {
                countriesMap[item.code] = item;
                item.searchableCode = "(" + item.code + ")";
            });

            _.assign($scope, {
                filteredList: $scope.items,
                selectedAllowed: [],
                selectedBlocked: [],
                selectedItems: [],
                items: items,
                loading: false,
                meta: {
                    filterValue: "",
                    sortBy: "name",
                    sortDirection: "asc",
                    quickFilterValue: "all"
                },

                /**
                 * Toggle the selection of an item
                 *
                 * @param {String} itemCode item code to toggle
                 * @param {String[]} list item list in which the code exists
                 */
                toggleSelect: function toggleSelect(itemCode, list) {

                    var idx = list.indexOf(itemCode);
                    if (idx > -1) {
                        list.splice(idx, 1);
                    } else {
                        list.push(itemCode);
                    }
                    $scope.updateSelectedBlocked();
                },

                /**
                 * Update which selected items are blocked and which are allowed
                 *
                 */
                updateSelectedBlocked: function updateSelectedBlocked() {
                    var allowed = [];
                    var blocked = [];
                    $scope.selectedItems.forEach(function(code) {
                        if (countriesMap[code].allowed) {
                            allowed.push(code);
                        } else {
                            blocked.push(code);
                        }
                    });
                    $scope.selectedBlocked = blocked;
                    $scope.selectedAllowed = allowed;
                },

                /**
                 * Toggle the selection of all or none of the items
                 *
                 */
                toggleSelectAll: function toggleSelectAll() {
                    if ($scope.allAreSelected()) {
                        $scope.deselectAll();
                    } else {
                        $scope.selectAll();
                    }
                },

                /**
                 * Select all of the items in the filtered list
                 *
                 */
                selectAll: function selectAll() {
                    $scope.selectedItems = $scope.filteredList.map(function(item) {
                        return item.code;
                    });
                    $scope.updateSelectedBlocked();
                },

                /**
                 * Deselect all the items in the filtered list
                 *
                 */
                deselectAll: function deselectAll() {
                    $scope.selectedItems = [];
                    $scope.updateSelectedBlocked();
                },

                /**
                 * Determine if all items are currently selected
                 *
                 * @returns {Boolean} all items are selected
                 */
                allAreSelected: function allAreSelected() {
                    return $scope.selectedItems.length && $scope.selectedItems.length === $scope.filteredList.length;
                },

                /**
                 * Does an item exist in a list
                 *
                 * @param {String} item to find in a list
                 * @param {String[]} list string list to search
                 *
                 * @returns {Boolean} the item exists in the list
                 */
                exists: function exists(item, list) {
                    return list.indexOf(item) > -1;
                },

                /**
                 * Translate a list of country codes to country objects
                 *
                 * @param {String[]} countryCodes list of country codes
                 * @returns {Object[]} list of country objectss
                 */
                getCountriesFromCodes: function getCountriesFromCodes(countryCodes) {
                    return countryCodes.map(function(countryCode) {
                        return countriesMap[countryCode];
                    });
                },

                /**
                 * Show the message that a successful blocking occurred
                 *
                 * @private
                 *
                 * @param {String[]} countryCodes list of country codes
                 * @returns {Promise} block promise
                 */
                _showBlockSuccessMessage: function _showBlockSuccessMessage(countryCodes) {
                    var countryNames = this.getCountriesFromCodes(countryCodes).map(function(country) {
                        return country.name;
                    });
                    var msg;
                    if (countryNames.length > COUNTRIES_MESSAGE_MAX) {
                        var shortList = countryNames.slice(0, COUNTRIES_MESSAGE_MAX);
                        var localeMsg = LOCALE.translatable("Your server will now block messages that originate in “[_1]”, “[_2]”, “[_3]”, “[_4]”, “[_5]”, “[_6]”, “[_7]”, “[_8]”, “[_9]”, “[_10]”, and [quant,_11,other country,other countries].");
                        msg = LOCALE.makevar.apply(LOCALE, [localeMsg].concat(shortList, countryNames.length - shortList.length));
                    } else {
                        msg = LOCALE.maketext("Your server will now block messages that originate in [list_or_quoted,_1].", countryNames);
                    }
                    $alertService.success(msg);
                },

                /**
                 * Show the message that a successful unblocking occurred
                 *
                 * @private
                 *
                 * @param {String[]} countryCodes list of country codes
                 * @returns {Promise} block promise
                 */
                _showUnblockSuccessMessage: function _showUnblockSuccessMessage(countryCodes) {
                    var countryNames = this.getCountriesFromCodes(countryCodes).map(function(country) {
                        return country.name;
                    });
                    var msg;
                    if (countryNames.length > COUNTRIES_MESSAGE_MAX) {
                        var shortList = countryNames.slice(0, COUNTRIES_MESSAGE_MAX);
                        var localeMsg = LOCALE.translatable("Your server will no longer block messages that originate in “[_1]”, “[_2]”, “[_3]”, “[_4]”, “[_5]”, “[_6]”, “[_7]”, “[_8]”, “[_9]”, “[_10]”, and [quant,_11,other country,other countries].");
                        msg = LOCALE.makevar.apply(LOCALE, [localeMsg].concat(shortList, countryNames.length - shortList.length));
                    } else {
                        msg = LOCALE.maketext("Your server will no longer block messages that originate in [list_or_quoted,_1].", countryNames);
                    }
                    $alertService.success(msg);
                },

                /**
                 * Block a list of countries by country codes
                 *
                 * @param {String[]} countries list of country codes
                 * @returns {Promise} block promise
                 */
                blockCountries: function blockCountries(countries) {
                    var allowedCountries = countries.filter(function(countryCode) {
                        return countriesMap[countryCode].allowed;
                    });
                    var countryObjs = $scope.getCountriesFromCodes(allowedCountries);
                    return $service.blockIncomingEmailFromCountries(allowedCountries)
                        .then($scope._showBlockSuccessMessage.bind($scope, allowedCountries))
                        .then(function() {
                            countryObjs.forEach(function(country) {
                                country.allowed = false;
                            });
                        })
                        .finally($scope.deselectAll)
                        .finally($scope.fetch);
                },

                /**
                 * Unblock a list of countries by country codes
                 *
                 * @param {String[]} countries list of country codes
                 * @returns {Promise} unblock promise
                 */
                unblockCountries: function unblockCountries(countries) {
                    var blockedCountries = countries.filter(function(countryCode) {
                        return !countriesMap[countryCode].allowed;
                    });
                    var countryObjs = $scope.getCountriesFromCodes(blockedCountries);
                    return $service.unblockIncomingEmailFromCountries(blockedCountries)
                        .then($scope._showUnblockSuccessMessage.bind($scope, blockedCountries))
                        .then(function() {
                            countryObjs.forEach(function(country) {
                                country.allowed = true;
                            });
                        })
                        .finally($scope.deselectAll)
                        .finally($scope.fetch);
                },

                /**
                 * Get a title text represenetative of the what a checkbox action would do
                 *
                 * @param {Object} countryObj country object
                 * @returns {String} phrase for checkbox
                 */
                getToggleSelectTitle: function getToggleSelectTitle(countryObj) {
                    if (this.exists(countryObj.code, this.selectedItems)) {
                        return LOCALE.maketext("Click to deselect “[_1]”.", countryObj.name);
                    }

                    return LOCALE.maketext("Click to select “[_1]”.", countryObj.name);
                },

                /**
                 * Get a title text representative of what a select all checkbox would do
                 *
                 * @returns {String} phrase for check
                 */
                getSelectAllToggleTitle: function getSelectAllToggleTitle() {
                    return this.allAreSelected() ? LOCALE.maketext("Click to deselect all countries.") : LOCALE.maketext("Click to select all countries.");
                },

                /**
                 * Toggle the blocked state of a country
                 *
                 * @param {String} countryObject
                 * @returns {Promise} promise for the update of state
                 */
                toggleBlocked: function toggleBlocked(countryObject) {
                    if (countryObject.allowed) {
                        return $service.blockIncomingEmailFromCountries([countryObject.code])
                            .then($scope._showBlockSuccessMessage.bind($scope, [countryObject.code]))
                            .then(function() {
                                countryObject.allowed = false;
                            })
                            .finally($scope.deselectAll)
                            .finally($scope.fetch);
                    } else {
                        return $service.unblockIncomingEmailFromCountries([countryObject.code])
                            .then($scope._showUnblockSuccessMessage.bind($scope, [countryObject.code]))
                            .then(function() {
                                countryObject.allowed = true;
                            })
                            .finally($scope.deselectAll)
                            .finally($scope.fetch);
                    }
                },

                /**
                 * Get the aria label for the toggle button
                 *
                 * @param {String} name name to be used in the string
                 * @param {Boolean} allowed whether it should be treated as allowed
                 *
                 * @returns {String} aria label
                 */
                getAriaLabel: function getAriaLabel(name, allowed) {
                    if (allowed) {
                        return LOCALE.maketext("Block email from “[_1]”.", name);
                    } else {
                        return LOCALE.maketext("Allow email from “[_1]”.", name);
                    }
                },

                /**
                 * Get the title label for the toggle button
                 *
                 * @param {String} name name to be used in the string
                 * @param {Boolean} allowed whether it should be treated as allowed
                 *
                 * @returns {String} title text
                 */
                getTitleLabel: function getTitleLabel(name, allowed) {
                    if (allowed) {
                        return LOCALE.maketext("Your server currently accepts messages that originate from servers in [_1].", name);
                    } else {
                        return LOCALE.maketext("Your server currently blocks messages that originate from servers in [_1].", name);
                    }
                },

                /**
                 * Called when the table needs to recaculate it's display
                 *
                 * @returns the updated filteredList
                 */
                fetch: function fetch() {
                    var filteredList = [];

                    // filter list based on search text
                    if ($scope.meta.filterValue !== "") {
                        filteredList = filters.filter($scope.items, $scope.meta.filterValue, false);
                    } else {
                        filteredList = $scope.items;
                    }

                    if ($scope.meta.quickFilterValue !== "all") {
                        filteredList = filters.filter(filteredList, { allowed: $scope.meta.quickFilterValue }, false);
                    }

                    // sort the filtered list
                    if ($scope.meta.sortDirection !== "" && $scope.meta.sortBy !== "") {
                        filteredList = filters.orderBy(filteredList, $scope.meta.sortBy, $scope.meta.sortDirection === "asc" ? false : true);
                    }

                    // update the total items after search
                    $scope.meta.totalItems = filteredList.length;

                    $scope.filteredList = filteredList;

                    return filteredList;
                }
            });

            // first page load
            $scope.fetch();
        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        module.directive(DIRECTIVE_NAME, function directiveFactory() {

            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                scope: {
                    "items": "=",
                    "onChange": "&onChange"
                },
                replace: true,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)
            };
        });

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "template": TEMPLATE_PATH,
        };
    });
