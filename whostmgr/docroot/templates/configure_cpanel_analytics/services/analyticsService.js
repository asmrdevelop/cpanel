/*
 * services/analyticsService.js                       Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define([
    "angular",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/services/APIService",
    "cjt/services/whm/nvDataService",
], function(
        angular,
        WHMAPI1_REQUEST
    ) {

    "use strict";

    var module = angular.module("whm.configureAnalytics.analyticsService", [
        "cjt2.services.api",
        "cjt2.services.whm.nvdata"
    ]);

    module.factory("analyticsService", [
        "$q",
        "APIService",
        "nvDataService",
        function(
            $q,
            APIService,
            nvDataService
        ) {

            var NO_MODULE = "";

            var AnalyticsService = function() {
                this.apiService = new APIService();
            };

            angular.extend(AnalyticsService.prototype, {

                /**
                 * Enable or disable Interface Analytics for the server.
                 *
                 * @method setInterfaceAnalytics
                 * @param {Boolean} shouldEnable   If true, Interface Analytics should be enabled.
                 * @return {Promise}               When resolved, the server has successfully recorded the user's choice.
                 */
                setInterfaceAnalytics: function(shouldEnable) {
                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "participate_in_analytics", {
                        enabled: shouldEnable ? 1 : 0,
                    });
                    return this.apiService.deferred(apiCall).promise;
                },

            });

            return new AnalyticsService();
        }
    ]);
});
