/*
# templates/upcp/index.js                         Copyright(c) 2020 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


/* global require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/directives/callout",
        "cjt/services/alertService",
        "shared/js/update_config/services/updateConfigService"
    ],
    function(angular, _) {
        "use strict";
        var appName = "whm.upcp";

        return function() {

            angular.module(appName, [
                "cjt2.config.whm.configProvider",
                "cjt2.whm",
                "whm.updateConfig.updateConfigurationService"
            ]);

            return require(
                [
                    "cjt/bootstrap"
                ],
                function(BOOTSTRAP) {
                    var app = angular.module(appName);
                    app.value("PAGE", PAGE);

                    app.controller("UpgradeController", ["$scope", "alertService", "updateConfigService",
                        function($scope, alertService, updateConfigService) {

                            $scope.enableAutomaticUpdates = function() {
                                return updateConfigService.enableAutomaticUpdates()
                                    .then(function(result) {
                                        $scope.allUpdatesDisabled = false;
                                        $scope.autoUpdatesEnabled = true;

                                        // Clear any previous errors before adding success message
                                        alertService.removeById("autoUpdateError");

                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("The system saved your changes."),
                                            closeable: false,
                                            id: "autoUpdateSuccess"
                                        });
                                    })
                                    .catch(function(error) {
                                        var errorMsgHtml = LOCALE.maketext("The system failed to save your new settings: [_1]", _.escape(error));
                                        alertService.add({
                                            type: "danger",
                                            message: errorMsgHtml,
                                            id: "autoUpdateError"
                                        });
                                    });
                            };

                            $scope.init = function() {
                                $scope.allUpdatesDisabled = PAGE.all_updates_disabled;
                                $scope.autoUpdatesEnabled = PAGE.auto_updates_enabled;
                            };

                            $scope.init();
                        }
                    ]);

                    BOOTSTRAP(document, appName);
                }
            );
        };
    }
);
