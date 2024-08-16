/*
 * cjt/config/webmail/configProvider.js               Copyright 2022 cPanel, L.L.C.
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

    var _componentConfigurationProvider;
    var config = angular.module("cjt2.config.webmail.configProvider", [
        "angular-growl",
        "cjt2.config.componentConfiguration",
        "cjt2.services.cpanel.nvdata",
    ]);

    var configureApplication = function(
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

        _componentConfigurationProvider = componentConfigurationProvider;
    };

    config.config([
        "$compileProvider",
        "growlProvider",
        "componentConfigurationProvider",
        configureApplication
    ]);

    var runApplication = function(
        nvDataService,
        $window,
        $log
    ) {
        if (_componentConfigurationProvider) {
            loadComponentConfiguration(_componentConfigurationProvider, nvDataService, $window, $log);
        }
    };

    config.run([
        "nvDataService",
        "$window",
        "$log",
        runApplication
    ]);

    return {
        configureApplication: configureApplication,
        runApplication: runApplication,
        getComponentConfigurationProvider: function() {
            return _componentConfigurationProvider;
        }
    };
});
