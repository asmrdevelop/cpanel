/*
# templates/feature/views/commonController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* ------------------------------------------------------------------------------
* DEVELOPER NOTES:
*  1) Put all common application functionality here, maybe
*-----------------------------------------------------------------------------*/

define(
    [
        "angular",
        "cjt/filters/wrapFilter",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "uiBootstrap"
    ],
    function(angular) {

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", ["ui.bootstrap", "ngSanitize"]);
        }

        var controller = app.controller(
            "commonController",
            ["$scope", "$location", "$rootScope", "alertService", "PAGE",
                function($scope, $location, $rootScope, alertService, PAGE) {

                // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Bind the alerts service to the local scope
                    $scope.alerts = alertService.getAlerts();

                    $scope.route = null;

                    /**
                 * Closes an alert and removes it from the alerts service
                 *
                 * @method closeAlert
                 * @param {String} index The array index of the alert to remove
                 */
                    $scope.closeAlert = function(id) {
                        alertService.remove(id);
                    };

                    /**
                 * Determines if the current view matches the supplied pattern
                 *
                 * @method isCurrentView
                 * @param {String} view The path to the view to match
                 */
                    $scope.isCurrentView = function(view) {
                        if ( $scope.route && $scope.route.$$route ) {
                            return $scope.route.$$route.originalPath === view;
                        }
                        return false;
                    };

                    // register listener to watch route changes
                    $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        $scope.route = next;
                    });
                }
            ]);


        return controller;
    }
);
