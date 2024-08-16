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
# templates/update_config/config.js                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */

define(
    'app/config',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/alert",
        "cjt/directives/callout",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "shared/js/update_config/services/updateConfigService",
    ],
    function(angular, $, _, LOCALE, PARSE) {

        "use strict";

        var app = angular.module("whm.updateConfig", ["whm.updateConfig.updateConfigurationService"]);

        app.controller("config", ["$scope", "updateConfigService", "alertService",
            function($scope, updateConfigService, alertService) {

                $scope.changeStagingDir = function() {

                    $scope.stagingDir = $scope.stagingSelection;

                    // add a slash if the path does not end in one
                    if (!/\/$/.test($scope.stagingSelection)) {
                        $scope.stagingDir += "/";
                    }
                };

                $scope.stagingdirOnChange = function() {
                    $scope.showStagingSubdir = toggleStagingSubdir();
                    $scope.stagingSelection = getPartition();

                };

                /**
                 * Decides whether to show the input group hint, based on whether or
                 * not the stagingDir is /usr/local/cpanel or not.
                 * @return boolean   True if the input group should be shown.
                 */
                function toggleStagingSubdir() {
                    return !/^\/usr\/local\/cpanel\/?$/.test($scope.stagingDir);
                }

                $scope.submitForm = function($event) {
                    if ($scope.isSaving) {
                        $event.preventDefault();
                        return;
                    }

                    $scope.isSaving = true;
                };

                /**
                 * Calls the service to enable automatic daily updates for cPanel, RPMs,
                 * and SpamAssassin. Triggers a success or error alert based on response
                 * from the service.
                 *
                 * @method - enableAutomaticUpdates
                 */
                $scope.enableAutomaticUpdates = function() {
                    return updateConfigService.enableAutomaticUpdates()
                        .then(function(result) {
                            $scope.autoUpdateEnabled = true;

                            // Clear any previous errors before adding success message
                            alertService.removeById("autoUpdateError");

                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("The system saved your changes. To update now, click [output,url,_1,here,id,_2].", "../scripts2/upcpform", "update-now-link"),
                                id: "autoUpdateSuccess"
                            });
                        })
                        .catch(function(error) {
                            var errorMessage = LOCALE.maketext("The system failed to save your new settings: [_1]", _.escape(error));
                            alertService.add({
                                type: "danger",
                                message: errorMessage,
                                id: "autoUpdateError"
                            });
                        });
                };

                $scope.toggleVersionDetails = function() {
                    $scope.showVersionDetails = !$scope.showVersionDetails;
                    if ($scope.showVersionDetails) {
                        $scope.additionalInfoText = LOCALE.maketext("Hide Additional Details");
                    } else {
                        $scope.additionalInfoText = LOCALE.maketext("Show Additional Details");
                    }
                };

                /**
                 * Provide a string with the appropriate tense, based on the expiration date vs the current date.
                 * @returns string   The localized string that tells when support for their custom build ended/will end.
                 */
                function getCustomTierExpirationStr() {
                    $scope.customTierIsExpired = $scope.customTierExpiration && $scope.customTierExpiration.getTime() < Date.now();
                    return $scope.customTier && $scope.customTierIsExpired ?
                        LOCALE.maketext("Support for this build ended on [_1].", $scope.customTierExpirationLocalized) :
                        LOCALE.maketext("Support for this build will end on [_1].", $scope.customTierExpirationLocalized);
                }

                /**
                 * Finds the partition that houses the stagingDir path.
                 * @return string   The matching partition path.
                 */
                function getPartition() {
                    var partitions = PAGE.partitions;

                    // Get rid of extra slashes from the user input
                    var normalizedStagingDir = $scope.stagingDir.replace(/(\/)+/g, "$1");
                    if (!/\/$/.test(normalizedStagingDir)) {
                        normalizedStagingDir += "/";
                    }

                    // Find all of the matching partitions
                    var partitionMatches = [];
                    var selectPartition = "";
                    var partitionPath;
                    if (partitions.length > 0) {
                        for (var i = 0; i < partitions.length; i++) {

                            partitionPath = partitions[i].path;
                            if (!/\/$/.test(partitionPath)) {
                                partitionPath += "/";
                            }

                            if (normalizedStagingDir.indexOf(partitionPath) === 0) {
                                partitionMatches.push(partitions[i].path);
                            }
                        }
                    }

                    // Find the best match partition
                    if (partitionMatches.length > 0) {
                        selectPartition = partitionMatches.reduce(function(a, b) {
                            return a.length > b.length ? a : b;
                        });
                    }

                    return selectPartition;
                }


                $scope.init = function() {
                    $scope.loading = true;
                    $scope.preventSumbit = PAGE.preventSumbit;
                    $scope.saved = PAGE.saved;
                    $scope.saveFailed = PAGE.save_failed;
                    $scope.tiers = PAGE.flat_tiers;
                    $scope.saveFailReason = PAGE.save_fail_reason;
                    $scope.currentVersion = PAGE.current_version;
                    $scope.currentMajorVersion = PAGE.current_major_version;
                    $scope.currentMajorVersionNoEleven = parseInt( $scope.currentVersion.split(".")[0] );
                    $scope.isDevVersion = $scope.currentMajorVersionNoEleven % 2 !== 0 ? true : false;
                    $scope.customTier = PAGE.custom_tier;
                    $scope.requiredFreeSpace = PAGE.required_free_space;
                    $scope.hostname = PAGE.hostname;
                    $scope.stagingDir = PAGE.upconf.staging_dir;
                    $scope.stagingSelection = getPartition();
                    $scope.showStagingSubdir = toggleStagingSubdir();
                    $scope.tierSelection = $scope.customTier ? $scope.customTier : PAGE.checked;
                    $scope.isSaving = false;

                    $scope.showVersionDetails = false;
                    $scope.additionalInfoText = LOCALE.maketext("Show Additional Details");

                    var customTierInfo = PAGE.custom_tier_info;
                    if (customTierInfo) {
                        $scope.customTierLatestBuild = customTierInfo.latest_build;

                        /**
                         * We offer support for the life of the tier, even if the installed
                         * version or custom tier have a lower expiration date, so we need to
                         * find the furthest date out to display.
                         */
                        var customTierExpiration = Math.max(customTierInfo.latest_build_expiration, customTierInfo.main_build_expiration);
                        if (customTierExpiration) {
                            $scope.customTierExpiration = new Date(customTierExpiration * 1000);
                            $scope.customTierExpirationLocalized = LOCALE.datetime($scope.customTierExpiration);
                            $scope.customTierExpiredWarningText = getCustomTierExpirationStr();
                        }
                    }

                    if ($scope.customTier && !customTierInfo.main_build) {
                        $scope.customTierInvalidWarningText = LOCALE.maketext(
                            "“[_1]” is not a supported named release tier. Your server won’t receive updates without a valid tier.",
                            $scope.customTier
                        );
                    }

                    $scope.hasCustomTierWarning = Boolean($scope.customTierInvalidWarningText || $scope.customTierExpiredWarningText);

                    $scope.upconf = PAGE.upconf;

                    $scope.autoUpdateEnabled = PARSE.parsePerlBoolean($scope.upconf.auto_update_enabled);

                    $scope.loading = false;
                };

                $scope.init();
            }
        ]);
    }
);

/*
# templates/update_config/index.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize"
    ],
    function(angular, $, _, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.updateConfig",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/views/applicationController",
                    "app/config",
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

