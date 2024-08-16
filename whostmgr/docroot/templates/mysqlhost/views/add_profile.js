/*
# templates/mysqlhost/views/add_profile.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */
/* jshint -W100 */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/models/MysqlProfile",
        "app/models/MysqlProfileUsingSsh",
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
    function(angular, _, LOCALE, MysqlProfile, MysqlProfileUsingSsh) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addProfileController",
            ["$scope", "$location", "$q", "$routeParams", "growl", "MySQLHostDataSource",
                function($scope, $location, $q, $routeParams, growl, MySQLHostDataSource) {

                    $scope.currentProfile = null;
                    $scope.workflow = {
                        currentProfileAuthType: "password",
                        disableSshProfileAuthType: false
                    };
                    $scope.ssh_keys = {};
                    $scope.enableCreateViaSSH = true;

                    $scope.disableSave = function(form) {
                        return (form.$dirty && form.$invalid);
                    };

                    $scope.saveProfile = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        // if the ssh auth type is enabled and a key has been selected, use it
                        if (!$scope.workflow.disableSshProfileAuthType && $scope.currentProfile.sshKey && $scope.currentProfile.sshKey.key) {
                            $scope.currentProfile.ssh_key = $scope.currentProfile.sshKey.key;
                        }

                        return MySQLHostDataSource.createProfile($scope.currentProfile)
                            .then( function() {
                                growl.success(LOCALE.maketext("You have successfully created the profile, “[_1]”.", _.escape($scope.currentProfile.name)));
                                $location.path("/profiles");
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.convertProfileType = function(type) {
                        if (type === "ssh") {
                            $scope.currentProfile = $scope.currentProfile.convertToProfileObject(MysqlProfileUsingSsh);

                            // default to grabbing the first key
                            $scope.currentProfile.sshKey = $scope.ssh_keys[0];
                        } else if (type === "mysql") {
                            $scope.currentProfile = $scope.currentProfile.convertToProfileObject(MysqlProfile);
                        }
                    };

                    $scope.requiresEscalation = function() {
                        return $scope.currentProfile &&
                        $scope.currentProfile.type === "ssh" &&
                        $scope.currentProfile.account &&
                        $scope.currentProfile.account.length > 0 &&
                        $scope.currentProfile.account !== "root";
                    };

                    function init() {

                        // which route is this?
                        $scope.currentRoute = $location.path();

                        if ($scope.currentRoute === "/profiles/newlocalhost") {
                            $scope.currentProfile = new MysqlProfile({
                                name: "localhost",
                                host: "localhost",
                                port: 3306,
                                account: "root"
                            });
                            $scope.enableCreateViaSSH = false;
                        } else {

                            // default profile type is the Mysql Using SSH credentials
                            $scope.currentProfile = new MysqlProfileUsingSsh();
                        }
                        $scope.currentProfile.sshKey = $scope.currentProfile.ssh_key;

                        if (typeof PAGE.key_list !== "undefined" && PAGE.key_list.length > 0) {
                            $scope.ssh_keys = PAGE.key_list;
                            $scope.currentProfile.sshKey = $scope.ssh_keys[0];
                        } else {
                            $scope.workflow.disableSshProfileAuthType = true;
                            $scope.workflow.currentProfileAuthType = "password";
                        }
                    }

                    init();
                }
            ]);

        return controller;
    }
);
