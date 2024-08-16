/*
# templates/hulkd/views/historyController.js      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/directives/countryCodesTableDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "countriesController",
            ["$scope","growl","HulkdDataSource","COUNTRY_CONSTANTS","COUNTRY_CODES","XLISTED_COUNTRIES",
            function($scope, $growl, $service, COUNTRY_CONSTANTS, COUNTRY_CODES, XLISTED_COUNTRIES) {

                function _parseCountries(countryCodes, xlistedCountries){
                    return countryCodes.map(function(countryCode){
                        countryCode.status = xlistedCountries[countryCode.code] || COUNTRY_CONSTANTS.UNLISTED;
                        return countryCode;
                    });
                }

                $scope.countries = _parseCountries(COUNTRY_CODES, XLISTED_COUNTRIES);

                var startingGrowl, successGrowl;

                $scope.countriesUpdated = function(whitelist, blacklist){
                    // Using growl for consistency, but this will have to be refactored later
                    if(successGrowl){
                        successGrowl.destroy();
                    }
                    startingGrowl = $growl.info(LOCALE.maketext("Updating the country whitelist and blacklist …"));
                    return $service.set_cphulk_config_keys({
                        "country_whitelist":whitelist.sort().join(","),
                        "country_blacklist":blacklist.sort().join(",")
                    }).then(function(xlistedCountries){
                        XLISTED_COUNTRIES = xlistedCountries;
                        $scope.countries = _parseCountries(COUNTRY_CODES, xlistedCountries);
                        startingGrowl.destroy();
                        successGrowl = $growl.success(LOCALE.maketext("Country whitelist and blacklist updated."));
                    });
                };

            }
        ]);

        return controller;
    }
);


