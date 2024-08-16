/*
# cpanel - base/frontend/jupiter/tools/views/nginxController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/util/locale",
        "jquery",

        // CJT
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "app/services/nginxService",
    ],
    function(angular, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "nginxController", [
                "$scope",
                "alertService",
                "nginxService",
                function(
                    $scope,
                    alertService,
                    nginxService) {

                    $scope.isRTL = PAGE.isRTL || false;
                    $scope.nginxCachingIsEnabled = PAGE.isNginxCachingEnabled || false;

                    $scope.nginxClearCache = function() {
                        return nginxService.clearCache().then(function() {
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("NGINX cache cleared."),
                                closeable: true,
                                replace: true,
                                autoClose: 10000,
                            });
                        });
                    };

                    $scope.toggleNginxCachingStatus = function() {
                        if ($scope.nginxCachingIsEnabled) {
                            return nginxService.disableCaching().then(function() {
                                $scope.nginxCachingIsEnabled = false;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("[asis,NGINX] cache is inactive."),
                                    closeable: true,
                                    replace: true,
                                    autoClose: 10000,
                                });
                            });
                        } else {
                            return nginxService.enableCaching().then(function() {
                                $scope.nginxCachingIsEnabled = true;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("[asis,NGINX] cache is active."),
                                    closeable: true,
                                    replace: true,
                                    autoClose: 10000,
                                });
                            });
                        }
                    };

                    $scope.showClearCacheButton = function() {
                        if ($scope.nginxCachingIsEnabled) {
                            return "ng-show";
                        } else {
                            return "ng-hide";
                        }
                    };
                },
            ]);

        return controller;
    }
);
