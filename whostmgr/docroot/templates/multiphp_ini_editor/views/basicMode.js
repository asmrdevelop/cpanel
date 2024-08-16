/*
 * templates/multiphp_ini_editor/views/basicMode.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "cjt/decorators/growlDecorator",
        "app/services/configService"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "basicMode",
            ["$scope", "$location", "$routeParams", "$timeout", "spinnerAPI", "alertService", "growl", "growlMessages", "configService", "PAGE",
                function($scope, $location, $routeParams, $timeout, spinnerAPI, alertService, growl, growlMessages, configService, PAGE) {

                // Setup data structures for the view
                    var alreadyInformed = false;
                    var infoGrowlHandle;
                    $scope.selectedVersion = "";
                    $scope.localeIsRTL = false;
                    $scope.loadingDirectiveList = false;
                    $scope.showEmptyMessage = false;
                    $scope.phpVersionsEmpty = true;
                    $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Not Available --[comment,used for highlight in select option]");

                    $scope.knobLabel = "\u00a0";

                    var resetForm = function() {

                        // Reset the directive list to empty.
                        $scope.directiveList = [];
                        $scope.showEmptyMessage = false;
                    };

                    $scope.loadDirectives = function() {
                        if ($scope.selectedVersion) {

                        // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();

                            spinnerAPI.start("loadingSpinner");
                            var version = $scope.selectedVersion;
                            $scope.loadingDirectiveList = true;
                            alreadyInformed = false;
                            return configService
                                .fetchBasicList(version)
                                .then(function(results) {

                                // Map the localized string for the directives' defaults
                                // to show them with the directive values.
                                    if (typeof (results.items) !== "undefined" && results.items.length > 0 ) {
                                        $scope.directiveList = results.items.map(function(item) {
                                            item.toggleValue = ( item.value === "On" ) ? true : false;
                                            var defaultPhpValue = item.default_value;
                                            if ( typeof item.cpanel_default !== "undefined" && item.cpanel_default !== null ) {
                                                defaultPhpValue = item.cpanel_default;
                                            }
                                            if ( item.type === "boolean" ) {
                                                defaultPhpValue = item.default_value === "1" ?
                                                    LOCALE.maketext("Enabled") : LOCALE.maketext("Disabled");
                                            }

                                            item.defaultText = LOCALE.maketext("[asis,PHP] Default: [output,class,_1,defaultValue]", defaultPhpValue);
                                            return item;
                                        });
                                    }
                                }, function(error) {
                                    growl.error(error);
                                    $scope.showEmptyMessage = true;
                                })
                                .then(function() {
                                    $scope.loadingDirectiveList = false;
                                    spinnerAPI.stop("loadingSpinner");
                                })
                                .finally(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.showEmptyMessage = $scope.selectedVersion !== "" && $scope.directiveList.length <= 0;
                                });
                        } else {
                            resetForm();
                        }
                    };

                    var informUser = function() {
                        if (!alreadyInformed) {
                            alreadyInformed = true;

                            growl.info(LOCALE.maketext("You must click “[_1]” to apply the new changes.", LOCALE.maketext("Apply")),
                                {
                                    onopen: function() {
                                        infoGrowlHandle = this;
                                    }
                                }
                            );
                        }
                    };

                    $scope.toggle_status = function(directive) {
                        if (directive.value === "On") {
                            directive.value = "Off";
                            directive.toggleValue = false;
                        } else {
                            directive.value = "On";
                            directive.toggleValue = true;
                        }
                        informUser();
                    };

                    $scope.directiveTextChange = function(directive) {
                        informUser();
                        var valInfo = configService.validateBasicDirective(directive.type, directive.value);
                        $scope.basicModeForm["txt" + directive.key].$setValidity("pattern", valInfo.valid);
                        directive.validationMsg = valInfo.valMsg;
                    };

                    $scope.disableApply = function() {
                        return ($scope.phpVersionsEmpty || !$scope.selectedVersion || !$scope.basicModeForm.$valid);
                    };

                    $scope.requiredValidation = function(directive) {
                        return (directive.type !== "string" && directive.type !== "boolean");
                    };

                    $scope.applyPhpSettings = function() {

                        if ($scope.basicModeForm.$valid) {

                            // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();
                            alreadyInformed = false;
                            if ( typeof infoGrowlHandle !== "undefined" ) {
                                infoGrowlHandle.destroy();
                            }
                            return configService.applySettings($scope.selectedVersion, $scope.directiveList)
                                .then(
                                    function(data) {
                                        if (data !== undefined) {
                                            growl.success(LOCALE.maketext("Successfully applied the settings to [asis,PHP] version “[_1]”.", $scope.selectedVersion));
                                        }
                                    }, function(error) {
                                        growl.error(error);
                                    });
                        }
                    };

                    var setDomainPhpDropdown = function(versionList) {

                        // versionList is sent to the function when the
                        // dropdown is bound the first time.
                        if (typeof (versionList) !== "undefined") {
                            $scope.phpVersions = versionList;
                        }

                        if ($scope.phpVersions.length > 0) {
                            $scope.phpVersionsEmpty = false;
                            $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Select a [asis,PHP] version --[comment,used for highlight in select option]");
                        } else {
                            $scope.phpVersionsEmpty = true;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {

                    // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        $scope.localeIsRTL = PAGE.locale_is_RTL ? true : false;

                        var versionListData = PAGE.php_versions;
                        var versionList = [];
                        if (versionListData.metadata.result) {

                        // Create a copy of the original list.
                            versionList = angular.copy(versionListData.data.versions);
                        } else {
                            growl.error(versionListData.metadata.reason);
                        }

                        // Bind PHP versions specific to domain dropdown list
                        setDomainPhpDropdown(versionList);
                    });
                }
            ]);

        return controller;
    }
);
