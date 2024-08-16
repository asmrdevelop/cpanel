/*
 * cjt/config/whm/configProvider.js                   Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 * This is a common configuration provider for most pages in WHM.
 */

/* global define: false */

define([
    "angular",
    "cjt/core",
    "cjt/config/componentConfigurationLoader",
    "angular-growl",
    "cjt/config/componentConfiguration",
    "cjt/services/whm/nvDataService"
], function(
        angular,
        CJT,
        loadComponentConfiguration
    ) {

    "use strict";

    var _componentConfigurationProvider;
    var config = angular.module("cjt2.config.whm.configProvider", [
        "angular-growl",
        "cjt2.config.componentConfiguration",
        "cjt2.services.whm.nvdata",
    ]);

    config.config([
        "$locationProvider",
        "$compileProvider",
        "growlProvider",
        "componentConfigurationProvider",
        function(
            $locationProvider,
            $compileProvider,
            growlProvider,
            componentConfigurationProvider
        ) {

            if (angular.isUndefined(CJT.config.html5Mode) || CJT.config.html5Mode) {
                $locationProvider.html5Mode(true);
                $locationProvider.hashPrefix("!");
            }

            if (CJT.config.debug) {

                // disable debug data when debugging
                $compileProvider.debugInfoEnabled(true);
            } else {

                // disable debug data for production
                $compileProvider.debugInfoEnabled(false);
            }

            // Setup the growl defaults if the growlProvider is loaded
            growlProvider.globalTimeToLive({ success: 5000, warning: -1, info: -1, error: -1 });
            growlProvider.globalDisableCountDown(true);

            _componentConfigurationProvider = componentConfigurationProvider;
        }
    ]);

    config.run([
        "nvDataService",
        "$window",
        "$log",
        function(
            nvDataService,
            $window,
            $log
        ) {
            if (_componentConfigurationProvider) {
                loadComponentConfiguration(_componentConfigurationProvider, nvDataService, $window, $log);
            }
        }
    ]);
});
