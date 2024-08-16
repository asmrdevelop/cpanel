/*
 * cjt/bootstrap.js                                Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 * This is the common bootstrap routine used by all applications.
 */

/* global define: false */

define([
    "angular",
    "cjt/core"
], function(
        angular,
        CJT
    ) {

    "use strict";

    return function(bootElement, applicationName) {
        var bootEl = bootElement || "#content";
        applicationName = applicationName || "App";

        if (CJT.applicationName === "cpanel" && bootEl !== "#content") {
            console.debug("Apps in cPanel that utilize the breadcrumbs need to bootstrap to #content to include that."); // eslint-disable-line no-console
        }

        if (angular.isString(bootEl)) {
            var els = angular.element(bootEl);
            if (els && els.length) {
                bootEl = els[0];
            } else {
                throw "Can not start up angular application since we can not find the element: " + bootElement;
            }
        }

        if (bootEl) {
            angular.bootstrap(bootEl, [applicationName]);
        } else {
            throw "Can not start up angular application since the element was not passed or is undefined";
        }
    };
}
);
