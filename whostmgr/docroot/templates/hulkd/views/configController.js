/*
# templates/hulkd/views/configController.js       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource",
        "app/directives/disableValidation"
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "configController",
            ["$scope", "HulkdDataSource", "growl", "PAGE",
                function($scope, HulkdDataSource, growl, PAGE) {

                    $scope.username_protection_level = "local";
                    $scope.username_protection_enabled = true;

                    function ignoreKeyDownForSpacebar(event) {

                        // prevent the spacebar from scrolling the window
                        if (event.keyCode === 32) {
                            event.preventDefault();
                        }
                    }

                    $scope.growlProtectionChangeRequiresSave = function() {
                        growl.warning(LOCALE.maketext("You changed the protection level of [asis,cPHulk]. Click Save to implement this change."));
                    };

                    $scope.$watch( function() {
                        return $scope.username_protection_enabled;
                    },
                    function(newValue, oldValue) {
                        if (newValue !== oldValue ) {
                            $scope.growlProtectionChangeRequiresSave();
                        }
                    }
                    );

                    $scope.$watch( function() {
                        return $scope.config_settings.ip_based_protection;
                    },
                    function(newValue, oldValue) {
                        if (newValue !== oldValue ) {
                            $scope.growlProtectionChangeRequiresSave();
                        }
                    }
                    );

                    $scope.align_username_protection_settings = function() {

                        // set up username protection to match the combined
                        // settings
                        if ($scope.config_settings.username_based_protection) {
                            $scope.username_protection_level = "both";
                            $scope.username_protection_enabled = true;
                        } else if ($scope.config_settings.username_based_protection_local_origin) {
                            $scope.username_protection_level = "local";
                            $scope.username_protection_enabled = true;
                        } else {
                            $scope.username_protection_enabled = false;
                        }
                    };

                    $scope.prepare_username_protection_settings_for_save = function() {
                        if (!$scope.username_protection_enabled) {
                            $scope.config_settings.username_based_protection_local_origin = false;
                            $scope.config_settings.username_based_protection = false;
                        } else if ($scope.username_protection_level === "local") {
                            $scope.config_settings.username_based_protection_local_origin = true;
                            $scope.config_settings.username_based_protection = false;
                        } else {
                            $scope.config_settings.username_based_protection = true;
                        }
                    };

                    $scope.handle_protection_keydown = function(event) {
                        ignoreKeyDownForSpacebar(event);
                    };

                    $scope.handle_protection_keyup = function(event, target) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            if ($scope.config_settings[target] !== void 0) {
                                if (target === "username") {
                                    $scope.username_protection_enabled = !$scope.username_protection_enabled;
                                } else {
                                    $scope.config_settings[target] = !$scope.config_settings[target];
                                }
                            }
                        }
                    };

                    $scope.collapse_keydown = function(event) {
                        ignoreKeyDownForSpacebar(event);
                    };


                    $scope.collapse_keyup = function(event, target) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            if ($scope[target] !== void 0) {
                                $scope[target] = !$scope[target];
                            }
                        }
                    };

                    $scope.disableSave = function(form) {
                        return form.$invalid || $scope.loadingPageData;
                    };

                    $scope.save = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        $scope.loadingPageData = true;

                        $scope.prepare_username_protection_settings_for_save();

                        return HulkdDataSource.save_config_settings($scope.config_settings)
                            .then(
                                function(data) {
                                    growl.success(LOCALE.maketext("The system successfully saved your [asis,cPHulk] configuration settings."));
                                    if (data.restart_ssh) {
                                        growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                    } else if (data.warning) {
                                        growl.warning(data.warning);
                                    }
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(function() {
                                $scope.loadingPageData = false;
                            });
                    };

                    $scope.fetch = function() {
                        if (_.isEmpty(HulkdDataSource.config_settings)) {
                            $scope.loadingPageData = true;
                            HulkdDataSource.load_config_settings()
                                .then(
                                    function(data) {
                                        $scope.config_settings = data;
                                        $scope.align_username_protection_settings();
                                    }, function(error) {
                                        growl.error(error);
                                    }
                                )
                                .finally(function() {
                                    $scope.loadingPageData = false;
                                });
                        } else {
                            $scope.config_settings = HulkdDataSource.config_settings;
                            $scope.align_username_protection_settings();
                        }

                    };

                    $scope.bruteInfoCollapse = true;
                    $scope.excessiveBruteInfoCollapse = true;
                    $scope.loadingPageData = false;

                    $scope.fetch();
                }
            ]);

        return controller;
    }
);
