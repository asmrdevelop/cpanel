/*
# templates/mysqlhost/views/profiles.js           Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/util/parse",
        "app/directives/mysqlhost_domain_validators",
        "cjt/validator/datatype-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "app/services/MySQLHostDataSource"
    ],
    function(angular, _, LOCALE, PARSE, MYSQL_DOMAIN_VALIDATORS) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "profilesController",
            ["$scope", "$uibModal", "$location", "$timeout", "growl", "MySQLHostDataSource", "growlMessages",
                function($scope, $uibModal, $location, $timeout, growl, MySQLHostDataSource, growlMessages) {

                    $scope.profiles = {};

                    $scope.activeProfile = "";
                    $scope.loadingProfiles = true;
                    $scope.modalInstance = null;
                    $scope.lastActivation = {
                        in_progress: false,
                        profile: "",
                        steps: [],
                        final_step: 0,
                        expanded: false
                    };
                    var monitorPromise;

                    $scope.messages = {
                        "DONE": LOCALE.maketext("This step completed."),
                        "FAILED": LOCALE.maketext("This step failed."),
                        "SKIPPED": LOCALE.maketext("This step was skipped."),
                        "INPROGRESS": LOCALE.maketext("This step is in progress.")
                    };

                    $scope.message = function(status) {
                        return $scope.messages[status];
                    };

                    $scope.profileListIsEmpty = function() {
                        if ($scope.loadingProfiles || ($scope.profiles && Object.keys($scope.profiles).length > 0)) {
                            return false;
                        }

                        return true;
                    };

                    $scope.confirmDeleteProfile = function(profileName) {
                        $scope.currentProfileName = profileName;
                        $scope.modalInstance = $uibModal.open({
                            templateUrl: "confirmprofiledeletion.html",
                            scope: $scope
                        });
                        return $scope.modalInstance.result
                            .then(function(profileName) {
                                return $scope.deleteProfile(profileName);
                            }, function() {
                                $scope.clearModalInstance();
                            });
                    };

                    $scope.confirmActivateProfile = function(profile) {
                        $scope.currentProfileName = profile.name;
                        $scope.is_not_supported = profile.is_local && !profile.is_supported;
                        $scope.modalInstance = $uibModal.open({
                            templateUrl: "confirmprofileactivation.html",
                            scope: $scope
                        });
                        return $scope.modalInstance.result
                            .then(function(profileName) {
                                return $scope.changeActiveProfile(profileName);
                            }, function() {
                                $scope.clearModalInstance();
                            });
                    };

                    $scope.clearModalInstance = function() {
                        if ($scope.modalInstance) {
                            $scope.modalInstance.close();
                            $scope.modalInstance = null;
                        }
                    };

                    $scope.disableProfileOperations = function(profileName) {
                        if ($scope.lastActivation.in_progress || $scope.profiles[profileName].active) {
                            return true;
                        }
                        return false;
                    };

                    function loadActivationSteps(obj) {
                        var i = $scope.lastActivation.final_step;
                        for (i; i < obj.steps.length; i++) {
                            $scope.lastActivation.steps.push(obj.steps[i]);
                        }

                        // iterate over the steps to make sure the status for each step is correct
                        for (var j = 0; j < obj.steps.length; j++) {
                            $scope.lastActivation.steps[j].status = obj.steps[j].status;
                        }
                        $scope.lastActivation.final_step = i;
                    }

                    $scope.monitorProfileChange = function(profileName) {
                        return MySQLHostDataSource.monitorActivation(profileName)
                            .then( function(data) {
                                if (!data.job_in_progress) {

                                    // disable the timeout
                                    $timeout.cancel(monitorPromise);

                                    loadActivationSteps(data.last_job_details);

                                    if ($scope.activeProfile && $scope.activeProfile !== "" && $scope.profiles[$scope.activeProfile]) {
                                        $scope.profiles[$scope.activeProfile].deactivate();
                                    }
                                    $scope.profiles[data.last_job_details.profile_name].activate();
                                    $scope.activeProfile = data.last_job_details.profile_name;
                                    $scope.lastActivation.in_progress = false;
                                    growlMessages.destroyAllMessages();
                                    growl.success(LOCALE.maketext("Activation completed for “[_1]”.", _.escape(profileName)));
                                    return null;
                                } else {
                                    $scope.lastActivation.in_progress = true;
                                    loadActivationSteps(data.job_in_progress);
                                    monitorPromise = $timeout(function() {
                                        return $scope.monitorProfileChange(data.job_in_progress.profile_name);
                                    }, 2000);
                                    return monitorPromise;
                                }
                            }, function(data) {

                                // disable the timeout
                                $timeout.cancel(monitorPromise);
                                loadActivationSteps(data.last_job_details);

                                var errorHtml = LOCALE.maketext("Activation failed for “[_1]” during step “[_2]” because of an error: [_3]",
                                    _.escape(data.last_job_details.profile_name),
                                    _.escape(data.last_job_details.steps[data.last_job_details.steps.length - 1].name),
                                    _.escape(data.last_job_details.steps[data.last_job_details.steps.length - 1].error)
                                );

                                errorHtml = MySQLHostDataSource.appendTroubleshootingLink({
                                    html: errorHtml,
                                    linkId: "monitor-troubleshoot-link-" + profileName,
                                });

                                growlMessages.destroyAllMessages();
                                growl.error(errorHtml);
                                $scope.lastActivation.in_progress = false;
                            });
                    };

                    $scope.changeActiveProfile = function(profileName) {
                        $scope.lastActivation.profile = profileName;
                        $scope.lastActivation.final_step = 0;
                        $scope.lastActivation.steps = [];
                        $scope.lastActivation.in_progress = true;
                        return MySQLHostDataSource.activateProfile(profileName)
                            .then( function() {
                                $scope.lastActivation.expanded = true;
                                growl.info(LOCALE.maketext("Activation in progress for “[_1]”.", _.escape(profileName)));
                                return $timeout(function() {
                                    return $scope.monitorProfileChange(profileName);
                                }, 2000);
                            }, function(error) {
                                growlMessages.destroyAllMessages();
                                growl.error(error);
                                $scope.lastActivation.in_progress = false;
                            });
                    };

                    $scope.deleteProfile = function(profileName) {
                        $scope.clearModalInstance();
                        return MySQLHostDataSource.deleteProfile(profileName)
                            .then( function() {
                                $scope.profiles = MySQLHostDataSource.profiles;
                                growl.success(LOCALE.maketext("You have successfully deleted the profile, “[_1]”.", _.escape(profileName)));
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.validateProfile = function(profileName) {
                        return MySQLHostDataSource.validateProfile(profileName)
                            .then( function() {
                                growl.success(LOCALE.maketext("The profile “[_1]” is valid.", _.escape(profileName)));
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.initialMonitorCheck = function() {
                        return MySQLHostDataSource.activationInProgress()
                            .then( function(last_activation) {
                                $scope.lastActivation.profile = last_activation.payload.profile_name;
                                loadActivationSteps(last_activation.payload);

                                if (last_activation.in_progress) {
                                    $scope.lastActivation.in_progress = true;
                                    return $scope.monitorProfileChange(last_activation.payload.profile_name);
                                }
                            });
                    };

                    $scope.loadProfiles = function() {
                        $scope.loadingProfiles = true;
                        return MySQLHostDataSource.loadProfiles()
                            .then( function() {
                                $scope.profiles = MySQLHostDataSource.profiles;
                                for (var name in $scope.profiles) {
                                    if ($scope.profiles[name].hasOwnProperty("active")) {
                                        if ($scope.profiles[name].active) {
                                            $scope.activeProfile = name;
                                            break;
                                        }
                                    }
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.loadingProfiles = false;
                            });
                    };

                    $scope.hasLocalhostProfile = function() {
                        for (var i = 0, keys = _.keys($scope.profiles), len = keys.length; i < len; i++) {
                            if ($scope.profiles[keys[i]].is_local) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.forceLoadProfiles = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        $scope.profiles = {};
                        $scope.loadProfiles();
                    };

                    $scope.goToAddProfile = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        return $location.path("/profiles/new");
                    };

                    $scope.goToAddLocalhostProfile = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        return $location.path("/profiles/newlocalhost");
                    };

                    var init = function() {
                        return $scope.loadProfiles()
                            .then(function() {
                                $scope.initialMonitorCheck();
                            });
                    };

                    init();
                }
            ]);

        return controller;
    }
);
