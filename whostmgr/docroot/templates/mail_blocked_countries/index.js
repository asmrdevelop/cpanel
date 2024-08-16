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
    [
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
