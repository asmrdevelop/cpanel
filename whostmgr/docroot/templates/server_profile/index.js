/*
#  cpanel - whostmgr/docroot/templates/server_profile/index.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/modules",
        "app/filters/rolesLocaleString",
        "app/services/serverProfileService"
    ],
    function(angular, CJT) {
        "use strict";

        var APP = "whm.serverProfile";
        var COMPONENT_NAME = "ServerProfileSelector";

        return function() {

            angular.module(APP, ["cjt2.config.whm.configProvider", "cjt2.whm", "cjt2.services.alert", "whm.serverProfile.rolesLocaleString", "whm.serverProfile.serverProfileService"]);

            require(
                [
                    "cjt/bootstrap",
                    "app/views/activatingProfileView",
                    "app/views/confirmProfileView",
                    "app/views/selectOptionsView",
                    "app/views/selectProfileView"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module(APP);
                    var LICENSE_BASED_SERVER_PROFILE = PAGE.availableProfiles.length === 1;
                    var currentProfile = PAGE.currentProfile;
                    var hasOptionalRoles = !!currentProfile.optional_roles.length;

                    app.value("PAGE", PAGE);
                    app.value("LICENSE_BASED_SERVER_PROFILE", LICENSE_BASED_SERVER_PROFILE);

                    app.config(["$routeProvider", function($routeProvider) {

                        // Do not include profile selection in routes if the license specifies a non-standard profile
                        if (!LICENSE_BASED_SERVER_PROFILE) {
                            $routeProvider.when("/selectProfile", {
                                controller: "selectProfileController",
                                templateUrl: CJT.buildFullPath("server_profile/views/selectProfileView.ptt")
                            });
                        }

                        $routeProvider.when("/selectOptions", {
                            controller: "selectOptionsController",
                            templateUrl: CJT.buildFullPath("server_profile/views/selectOptionsView.ptt")
                        });

                        $routeProvider.when("/confirmProfile", {
                            controller: "confirmProfileController",
                            templateUrl: CJT.buildFullPath("server_profile/views/confirmProfileView.ptt")
                        });

                        $routeProvider.when("/activatingProfile", {
                            controller: "activatingProfileController",
                            templateUrl: CJT.buildFullPath("server_profile/views/activatingProfileView.ptt")
                        });

                        // If the license specifies the profile, go straight to options
                        if (LICENSE_BASED_SERVER_PROFILE) {
                            $routeProvider.otherwise("/selectOptions");
                        } else {
                            $routeProvider.otherwise("/selectProfile");
                        }

                    }]);

                    app.controller("baseController", ["$scope", "componentSettingSaverService", "$location", "$timeout",
                        function($scope, csss, $location, $timeout) {

                            $scope.licenseBasedServerProfile = LICENSE_BASED_SERVER_PROFILE;
                            $scope.noOptionalRoles = !hasOptionalRoles;

                            $scope.$on("ActivateProfileEvent", function() {
                                $scope.activationInitiated = true;
                            });

                            $scope.$on("$destroy", function() {
                                csss.unregister(COMPONENT_NAME);
                            });

                            $scope.dismissWarning = function() {

                                csss.set(COMPONENT_NAME, {
                                    dismissedWarning: true
                                });

                                $scope.dismissedWarning = true;
                            };

                            var register = csss.register(COMPONENT_NAME);
                            if ( register ) {
                                register.then(function(result) {
                                    if ( result && result.dismissedWarning !== undefined ) {
                                        $scope.dismissedWarning = true;
                                    }
                                }).finally(function() {
                                    $location.path("/selectProfile");
                                    $timeout(function() {
                                        $scope.loaded = true;
                                    });
                                });
                            } else {
                                $location.path("/selectProfile");
                                $timeout(function() {
                                    $scope.loaded = true;
                                });
                            }

                        }]
                    );

                    BOOTSTRAP("#contentContainer", APP);
                }
            );
        };
    }
);
