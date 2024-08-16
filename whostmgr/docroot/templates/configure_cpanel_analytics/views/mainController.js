/*
 # cpanel - whostmgr/docroot/templates/configure_cpanel_analytics/views/mainController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-env amd */

define([
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
