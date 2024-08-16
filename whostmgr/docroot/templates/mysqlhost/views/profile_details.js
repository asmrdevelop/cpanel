/*
# templates/mysqlhost/views/profile_details.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

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
        "cjt/directives/actionButtonDirective",
        "app/services/MySQLHostDataSource",
        "app/directives/mysqlhost_domain_validators"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "profileDetailsController",
            ["$scope", "$location", "$q", "$routeParams", "growl", "MySQLHostDataSource",
                function($scope, $location, $q, $routeParams, growl, MySQLHostDataSource) {

                    $scope.currentProfile = null;
                    $scope.loadingProfiles = false;

                    $scope.disableSave = function(form) {
                        return (form.$dirty && form.$invalid) || $scope.loadingProfiles;
                    };

                    $scope.saveProfile = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        return MySQLHostDataSource.updateProfile($scope.currentProfile)
                            .then( function() {
                                growl.success(LOCALE.maketext("You have successfully updated the profile, “[_1]”.", _.escape($scope.currentProfile.name)));
                                $location.path("/profiles");
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.loadProfiles = function() {
                        $scope.loadingProfiles = true;
                        return MySQLHostDataSource.loadProfiles()
                            .then( function() {
                                $scope.loadingProfiles = false;
                            }, function(error) {
                                growl.error(error);
                                $scope.loadingProfiles = true;
                            });
                    };

                    $scope.loadProfileData = function(profileName) {
                        var profileData = MySQLHostDataSource.profiles[profileName];
                        if (typeof profileData !== "undefined") {
                            $scope.currentProfile = profileData;
                            return true;
                        } else {
                            return false;
                        }
                    };

                    function init() {

                    // we are trying to load a particular profile. does the profile exist?
                        $scope.loadProfiles()
                            .then(function() {
                                var result = $scope.loadProfileData($routeParams.profileName);
                                if (!result) {

                                // the profile does not exist, take them back to the profile page
                                    $location.path("profiles");
                                } else {
                                    $scope.loadingProfiles = false;
                                }
                            });
                    }

                    init();
                }
            ]);

        return controller;
    }
);
