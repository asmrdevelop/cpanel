/*
# countriesService.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/services/countriesService',[
        "angular",
        "lodash",
        "cjt/io/whm-v1-request",
        "cjt/modules",
        "cjt/io/api",
        "cjt/io/whm-v1",
        "cjt/services/APICatcher"
    ],
    function(angular, _, APIRequest) {

        "use strict";

        var MODULE_NAMESPACE = "whm.eximBlockCountries.services.countries";
        var SERVICE_NAME = "eximBlockCountries";
        var MODULE_REQUIREMENTS = [ "cjt2.services.apicatcher" ];
        var SERVICE_INJECTABLES = ["APICatcher", "$q"];

        /**
         *
         * Service Factory to generate the Exim Block Countries service
         *
         * @module countriesService
         * @memberof whm.eximBlockCountries
         *
         * @param {Object} APICatcher base service
         * @returns {Service} instance of the eximBlockCountries service
         */
        var SERVICE_FACTORY = function SERVICE_FACTORY(APICatcher, $q) {

            var Service = function Service() {};

            Service.prototype = Object.create(APICatcher);

            _.assign(Service.prototype, {

                /**
                 * Wrapper for building an apiCall
                 *
                 * @private
                 *
                 * @param {String} module module name to call
                 * @param {String} func api function name to call
                 * @param {Object} args key value pairs to pass to the api
                 * @returns {UAPIRequest} returns the api call
                 *
                 * @example _apiCall( "", "list_blocked_incoming_email_countries")
                 */
                _apiCall: function _createApiCall(module, func, args) {
                    var apiCall = new APIRequest.Class();
                    apiCall.initialize(module, func, args);
                    return apiCall;
                },

                /**
                 * List the Currently Blocked Email Countries
                 *
                 * @returns {Promise<Object[]>} List of blocked countries
                 *
                 * @example $service.listBlockedIncomingEmailCountries();
                 */
                listBlockedIncomingEmailCountries: function listBlockedIncomingEmailCountries() {
                    if (_.isArray(PAGE.blocked_incoming_email_countries)) {
                        return $q.resolve(PAGE.blocked_incoming_email_countries);
                    }

                    var apiCall = this._apiCall("", "list_blocked_incoming_email_countries");
                    return this._promise(apiCall).then(function _parseBlockedCountries(result) {
                        return result && result.data || [];
                    });
                },

                /**
                 * List the Countries With Known IP Ranges
                 *
                 * @returns {Promise<Object[]>} List of countries
                 *
                 * @example $service.getCountriesWithKnownIPRanges();
                 */
                getCountriesWithKnownIPRanges: function getCountriesWithKnownIPRanges() {
                    if (_.isArray(PAGE.countries_with_known_ip_ranges)) {
                        return $q.resolve(PAGE.countries_with_known_ip_ranges);
                    }
                    var apiCall = this._apiCall("", "get_countries_with_known_ip_ranges");
                    return this._promise(apiCall).then(function _parseCountries(result) {
                        return result && result.data || [];
                    });
                },

                _verifyCountryCodesArray: function _verifyCountryCodesArray(countryCodes) {
                    if (!_.isArray(countryCodes)) {
                        throw "countryCodes must be an array";
                    }
                    var notStringIndex = _.findIndex(countryCodes, function(countryCode) {
                        if (typeof (countryCode) !== "string") {
                            return true;
                        }
                        return false;
                    });
                    if (notStringIndex !== -1) {
                        var msg = "";
                        msg += "countryCodes must be an array of country code strings. ";
                        msg += "“" + notStringIndex + "” is not a string (" + (typeof countryCodes[notStringIndex]) + ")";
                        throw msg;
                    }

                    return true;
                },

                /**
                 * Block a Country
                 *
                 * @param {String[]} countryCodes Country code to block
                 *
                 * @returns {Promise}
                 * @throws an error if countryCodes is not an array
                 * @throws an error if countryCodes is not an array of strings
                 *
                 * @example $service.blockIncomingEmailFromCountries('RU');
                 */
                blockIncomingEmailFromCountries: function blockIncomingEmailFromCountries(countryCodes) {
                    this._verifyCountryCodesArray(countryCodes);
                    var apiCall = this._apiCall("", "block_incoming_email_from_country", { country_code: countryCodes });

                    return this._promise(apiCall);
                },

                /**
                 * Unblock a Country
                 *
                 * @param {String[]} countryCode Country code to unblock
                 *
                 * @returns {Promise}
                 * @throws an error if countryCodes is not an array
                 * @throws an error if countryCodes is not an array of strings
                 *
                 * @example $service.unblockIncomingEmailFromCountries('RU');
                 */
                unblockIncomingEmailFromCountries: function unblockIncomingEmailFromCountries(countryCodes) {
                    this._verifyCountryCodesArray(countryCodes);
                    var apiCall = this._apiCall("", "unblock_incoming_email_from_country", { country_code: countryCodes });

                    return this._promise(apiCall);
                },

                /**
                 * Wrapper for .promise method from APICatcher
                 *
                 * @private
                 *
                 * @param {Object} apiCall api call to pass to .promise
                 * @returns {Promise}
                 *
                 * @example $service._promise( $service._apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } ) );
                 */
                _promise: function _promise() {

                    // Because nested inheritence is annoying
                    return APICatcher.promise.apply(this, arguments);
                }
            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);

/*
# countryCodesTableDirective.js                      Copyright 2022 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/countryCodesTableDirective',[
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

/*
# countriesController.js                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/countriesController',[
        "angular",
        "lodash",
        "cjt/core",
        "app/services/countriesService",
        "app/directives/countryCodesTableDirective",
    ],
    function(angular, _, CJT, CountriesService, CountryCodesTableDirective) {

        "use strict";

        var MODULE_NAMESPACE = "whm.eximBlockCountries.views.countries";
        var TEMPLATE_URL = "views/countries.phtml";
        var MODULE_DEPENDANCIES = [
            CountriesService.namespace,
            CountryCodesTableDirective.namespace
        ];
        var COUNTRY_CODES_VAR = "COUNTRY_CODES";
        var BLOCKED_COUNTRIES_VAR = "BLOCKED_COUNTRIES";

        var CONTROLLER_NAME = "CountriesController";

        /**
         *
         * View Controller for Countries list
         *
         * @module countriesController
         * @memberof whm.eximBlockCountries
         *
         * @param {Object} $scope angular scope instance
         * @param {Object[]} COUNTRY_CODES current list of country codes
         * @param {Object[]} BLOCKED_COUNTRIES current liste of blocked countries
         */


        var CONTROLLER_INJECTABLES = ["$scope", COUNTRY_CODES_VAR, BLOCKED_COUNTRIES_VAR];
        var CONTROLLER = function CountriesController($scope, COUNTRY_CODES, BLOCKED_COUNTRIES) {
            var countryCodeMap = {};
            var countries = COUNTRY_CODES;
            if (!_.isArray(COUNTRY_CODES)) {
                throw "COUNTRY_CODES is not an array";
            }
            if (!_.isArray(BLOCKED_COUNTRIES)) {
                throw "BLOCKED_COUNTRIES is not an array";
            }

            // Translated Blocked to allowed
            countries.forEach(function _parseCountry(country) {
                countryCodeMap[country.code] = country;
                country.allowed = true;
            });
            BLOCKED_COUNTRIES.forEach(function _parseBlockedCountry(country) {
                var countryCode = country.country_code;
                if (countryCodeMap[countryCode]) {
                    countryCodeMap[countryCode].allowed = false;
                }
            });
            $scope.countries = countries;
        };

        var app = angular.module(MODULE_NAMESPACE, MODULE_DEPENDANCIES);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES.concat(CONTROLLER));

        var resolver = {};
        resolver[COUNTRY_CODES_VAR] = [CountriesService.serviceName, function($service) {
            return $service.getCountriesWithKnownIPRanges();
        }];
        resolver[BLOCKED_COUNTRIES_VAR] = [CountriesService.serviceName, function($service) {
            return $service.listBlockedIncomingEmailCountries();
        }];

        return {
            "path": "/",
            "controller": CONTROLLER_NAME,
            "class": CONTROLLER,
            "template": TEMPLATE_URL,
            "namespace": MODULE_NAMESPACE,
            "resolver": resolver
        };
    }
);

/*
# index.js                                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */
/* jshint -W100 */
/* eslint-disable camelcase */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "app/views/countriesController",
        "cjt/modules",
        "cjt/directives/alertList",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
        "ngAnimate"
    ],
    function(angular, $, _, CountriesController) {

        "use strict";

        /**
         *
         * App to Block Incoming Emails by Country
         *
         * @module whm.eximBlockCountries
         *
         */

        return function() {

            var MODULE_NAME = "whm.eximBlockCountries";

            var appModule = angular.module(MODULE_NAME, [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "cjt2.whm",
                CountriesController.namespace
            ]);

            var app = require(["cjt/bootstrap"], function(BOOTSTRAP) {

                appModule.value("PAGE", PAGE);

                appModule.controller("BaseController", ["$rootScope", "$scope",
                    function($rootScope, $scope) {

                        $scope.loading = false;
                        $rootScope.$on("$routeChangeStart", function() {
                            $scope.loading = true;
                        });
                        $rootScope.$on("$routeChangeSuccess", function() {
                            $scope.loading = false;
                        });
                        $rootScope.$on("$routeChangeError", function() {
                            $scope.loading = false;
                        });
                    }
                ]);

                appModule.config(["$routeProvider", "$animateProvider",
                    function($routeProvider, $animateProvider) {

                        $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                        $routeProvider.when(CountriesController.path, {
                            controller: CountriesController.controller,
                            templateUrl: CountriesController.template,
                            resolve: CountriesController.resolver
                        });

                        $routeProvider.otherwise({
                            "redirectTo": CountriesController.path
                        });
                    }
                ]);

                BOOTSTRAP("#content", MODULE_NAME);

            });

            return app;
        };
    }
);

