/*
# templates/update_config/services/updateConfigService.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'shared/js/update_config/services/updateConfigService',[
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/io/api",
        "cjt/services/APIService",
    ],
    function(angular, APIREQUEST) {

        "use strict";

        var app = angular.module("whm.updateConfig.updateConfigurationService", []);

        app.factory(
            "updateConfigService",
            ["$q", "APIService", function($q, APIService) {

                var UpdateConfigService = function() {
                    APIService.call(this);
                };
                UpdateConfigService.prototype = Object.create(APIService.prototype);

                angular.extend(UpdateConfigService.prototype, {

                    /**
                     * Enables automatic daily updates for cPanel, RPMs, and SpamAssassin.
                     *
                     * @method - enableAutomaticUpdates
                     * @returns {Promise} - When resolved, the config settings have been saved. When rejected, returns a descriptive error message if available.
                     */
                    enableAutomaticUpdates: function enableAutomaticUpdates() {
                        var apiCall = new APIREQUEST.Class();
                        var apiArgs = {
                            "UPDATES": "daily",
                            "RPMUP": "daily",
                            "SARULESUP": "daily"
                        };

                        apiCall.initialize("", "update_updateconf", apiArgs);

                        return this.deferred(apiCall).promise;
                    }
                });

                return new UpdateConfigService();
            }
            ]);
    }
);

/*
# templates/upcp/index.js                         Copyright(c) 2020 cPanel, Inc.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


/* global require: false, define: false, PAGE: false */

define(
    'app/index',[
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

