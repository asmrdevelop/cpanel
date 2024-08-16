/*
 * # cjt/services/onBeforeUnload.js                  Copyright 2022 cPanel, L.L.C.
 * #                                                        All rights reserved.
 * # copyright@cpanel.net                                      http://cpanel.net
 * # This code is subject to the cPanel license. Unauthorized copying is prohibited
 * */

/* global define: false */

define([
    "angular",
],
function(angular) {
    "use strict";

    /* A tiny service to listen for window.onbeforeunload and record
     * when that event has happened.
     *
     * Example usage:
     *
     *  var windowIsUnloading = onBeforeUnload.windowIsUnloading();
     */

    var module = angular.module("cjt2.services.onBeforeUnload", []);

    var windowIsUnloading = false;

    function _windowIsUnloading() {
        return windowIsUnloading;
    }

    function _onBeforeUnload() {
        windowIsUnloading = true;
    }
    window.addEventListener("beforeunload", _onBeforeUnload);

    module.factory("onBeforeUnload", function() {
        return {
            _onBeforeUnload: _onBeforeUnload,    // exposed for tests
            windowIsUnloading: _windowIsUnloading,
        };
    } );
});
