/*
 * cjt/config/componentConfigurationLoader.js         Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
    "cjt/util/locale",
],
function(
        LOCALE
    ) {
    "use strict";

    var COMPONENT_LIST = [
        "common-alertList",
    ];

    return function(provider, nvDataService, $window, $log) {
        if (!provider) {
            throw new Error(LOCALE.maketext("You must specify the [_1] argument.", "provider"));
        }

        if (!nvDataService) {
            throw new Error(LOCALE.maketext("You must specify the [_1] argument.", "nvDataService"));
        }

        if (!$window) {
            throw new Error(LOCALE.maketext("You must specify the [_1] argument.", "$window"));
        }

        if (!$log) {
            throw new Error(LOCALE.maketext("You must specify the [_1] argument.", $log));
        }

        // Handle prefetch first
        var needed = [];
        if ($window.PAGE && $window.PAGE.COMPONENT_SETTINGS) {
            COMPONENT_LIST.forEach(function(fullComponentName) {
                var parts  = fullComponentName.split("-");
                var componentName = parts[1];
                if ($window.PAGE.COMPONENT_SETTINGS.hasOwnProperty(fullComponentName)) {
                    provider.setComponent(componentName, $window.PAGE.COMPONENT_SETTINGS[fullComponentName]);
                } else {
                    needed.push(fullComponentName);
                }
            });
        } else {
            needed = COMPONENT_LIST;
        }

        if (!needed.length) {
            return;
        }

        // Handle fetching any properties missing from the prefetch
        nvDataService.getObject(needed).then(
            function(nvdata) {
                needed.forEach(function(fullComponentName) {
                    var componentSettings = nvdata[fullComponentName];

                    // Parse the nvdata's value to json object before using it.
                    if (typeof componentSettings === "string") {
                        try {
                            componentSettings = JSON.parse(componentSettings);
                        } catch (e) {
                            componentSettings = null;
                        }

                    }
                    var parts  = fullComponentName.split("-");
                    var componentName = parts[1];
                    provider.setComponent(componentName, componentSettings);
                });
            },
            function(error) {
                $log.error(LOCALE.maketext("The system failed to retrieve the account-wide personalization preferences with the error: [_1]", error));
            }
        );
    };
});
