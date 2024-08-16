/*
# countriesController.js                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
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
