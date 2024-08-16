/*
 * services/analyticsService.js                       Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/services/analyticsService',[
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

/*
 # cpanel - whostmgr/docroot/templates/configure_cpanel_analytics/views/mainController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-env amd */

define('app/views/mainController',[
    "angular",
    "cjt/util/locale",
    "ngSanitize",
    "uiBootstrap",
    "cjt/directives/toggleSwitchDirective",
    "cjt/services/alertService",
    "app/services/analyticsService",
], function(angular, LOCALE) {

    "use strict";

    angular
        .module("whm.configureAnalytics.mainController", [
            "ngSanitize",
            "ui.bootstrap.collapse",
            "whm.configureAnalytics.analyticsService",
            "cjt2.directives.toggleSwitch",
            "cjt2.services.alert",
        ])
        .controller("mainController", [
            "PAGE",
            "analyticsService",
            "alertService",
            "$q",
            MainController,
        ]);

    function MainController(PAGE, analyticsService, alertService, $q) {
        this.analyticsService = analyticsService;
        this.alertService = alertService;
        this.$q = $q;

        // Initial view state
        this.isUserChoiceEnabled     = PAGE.isUserChoiceEnabled;
        this.isTrialLicense          = PAGE.isTrialLicense;
        this.isEnabledForCurrentUser = PAGE.isEnabledForUser;
        this.defaultToOn             = PAGE.defaultToOn;
        this.isRootUser              = PAGE.isRootUser;

        this.isCollapsed = true;
    }

    angular.extend(MainController.prototype, {

        /**
         * Toggle Interface Analytics on or off, depending on its current state.
         *
         * @method toggleInterfaceAnalytics
         * @return {Promise}   When resolved, the setting has successfully been toggled on the backend.
         */
        toggleInterfaceAnalytics: function() {
            var self = this;
            this.isUserChoiceEnabled = !this.isUserChoiceEnabled;
            return this.analyticsService.setInterfaceAnalytics(this.isUserChoiceEnabled).catch(
                function failure(error) {

                    if (self.isUserChoiceEnabled) {
                        self.alertService.add({
                            message: LOCALE.maketext("The system failed to enable Interface Analytics participation: [_1]", error),
                            type: "danger",
                            closeable: true,
                            id: "interface-analytics-enable-failed",
                        });
                    } else {
                        self.alertService.add({
                            message: LOCALE.maketext("The system failed to disable Interface Analytics participation: [_1]", error),
                            type: "danger",
                            closeable: true,
                            id: "interface-analytics-disable-failed",
                        });
                    }

                    self.isUserChoiceEnabled = !self.isUserChoiceEnabled;

                    return self.$q.reject(error);
                }
            );
        },

        /**
         * Toggle whether or not to show the extended information for a particular section.
         */
        toggleIsCollapsed: function() {
            this.isCollapsed = !this.isCollapsed;
        },
    });

    return MainController;

});

/*
# cpanel - whostmgr/docroot/templates/configure_cpanel_analytics/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-env amd */

define(
    'app/index',[
        "angular",
        "cjt/util/parse",
        "cjt/modules",
        "ngRoute",
        "ngSanitize",
        "uiBootstrap",
    ],
    function(angular, PARSE) {

        "use strict";

        return function() {

            require(
                [
                    "cjt/bootstrap",
                    "cjt/directives/alertList",
                    "app/views/mainController",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.configureAnalytics", [
                        "cjt2.config.whm.configProvider", // This needs to load before ngRoute
                        "ngRoute",
                        "ui.bootstrap",
                        "cjt2.directives.alertList",
                        "whm.configureAnalytics.mainController",
                    ]);

                    app.config([
                        "$routeProvider", "$locationProvider",
                        function($routeProvider, $locationProvider) {

                            $routeProvider.when("/main", {
                                controller: "mainController",
                                controllerAs: "vm",
                                templateUrl: "configure_cpanel_analytics/views/mainView.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/main",
                            });
                        },
                    ]);

                    app.value("PAGE", window.PAGE);

                    BOOTSTRAP("#content", "whm.configureAnalytics");

                });
        };
    }
);

