/*
 * cjt/config/cpanel/configProvider.js                Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 * This is a common configuration provider for most pages in cPanel.
 */

/* global define: false */

define([
    "angular",
    "cjt/core",
    "cjt/config/componentConfigurationLoader",
    "angular-growl",
    "cjt/config/componentConfiguration",
    "cjt/services/cpanel/nvDataService"
],
function(
        angular,
        CJT,
        loadComponentConfiguration
    ) {
    "use strict";

    var _pendingForcePasswordChange;
    var _componentConfigurationProvider;
    var config = angular.module("cjt2.config.cpanel.configProvider", [
        "angular-growl",
        "cjt2.config.componentConfiguration",
        "cjt2.services.cpanel.nvdata",
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

            _pendingForcePasswordChange = PAGE.skipNotificationsCheck || false;

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
            if (_pendingForcePasswordChange) return;

            if (_componentConfigurationProvider) {
                loadComponentConfiguration(_componentConfigurationProvider, nvDataService, $window, $log);
            }
        }
    ]);

});
