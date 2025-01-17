/*
# mail/authentication/views/manageController.js   Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W098 */

define(
    [
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService"
    ],
    function(angular, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "manageController", [
                "$scope",
                "$routeParams",
                "manageService",
                "alertService",
                function(
                    $scope,
                    $routeParams,
                    manageService,
                    alertService) {

                    $scope.unlink = function(provider, displayName) {
                        var promise = manageService.unlink(provider.provider_id, provider.subject_unique_identifier, $routeParams.username).then(function() {
                            manageService.fetch_links($routeParams.username).then(function() {
                                $scope.providers = manageService.get_links();
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system encountered an error while it tried to retrieve results, please refresh the interface: [_1]", error),
                                    closeable: true,
                                    replace: false,
                                    group: "emailExternalAuth"
                                });
                                provider.disabled = 0;
                            });
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully unlinked the “[_1]” account “[_2]”", displayName, provider.preferred_username),
                                closeable: true,
                                replace: false,
                                autoClose: 10000,
                                group: "emailExternalAuth"
                            });
                        }, function(error) {
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system encountered an error while it tried to retrieve results, please refresh the interface: [_1]", error),
                                closeable: true,
                                replace: false,
                                group: "emailExternalAuth"
                            });
                            provider.disabled = 0;
                        });

                        return promise;
                    };

                    $scope.init = function() {
                        $scope.username = $routeParams.username;
                        $scope.locale = LOCALE;
                        $scope.providers = manageService.get_links();
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
