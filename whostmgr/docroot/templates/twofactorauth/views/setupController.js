/*
# twofactorauth/views/setupController.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/directives/create_qrcode",
        "app/services/tfaData"
    ],
    function(angular, LOCALE, PARSE) {

        var app = angular.module("App");

        var controller = app.controller(
            "setupController",
            ["$scope", "TwoFactorData", "growl", "$timeout", "$q", "$uibModal",
                function($scope, TwoFactorData, growl, $timeout, $q, $uibModal) {
                    var setup = this;

                    setup.setup_data = {};
                    setup.setup_data.user = TwoFactorData.currentUser.user_name;
                    setup.isEnabled = TwoFactorData.currentUser.is_enabled;
                    setup.loading = false;
                    setup.settingUp = false;
                    setup.isSaving = false;
                    setup.isReconfigure = false;

                    setup.getSetupData = function() {
                        return TwoFactorData.generateSetupData()
                            .then(function(result) {
                                setup.setup_data.otpauth_str = result.otpauth_str;
                                setup.setup_data.secret = result.secret;
                            })
                            .catch(function(error) {
                                growl.error(error);
                            });
                    };

                    setup.disableSave = function(form) {
                        return (form.$invalid);
                    };

                    setup.goToSetup = function() {
                        setup.isReconfigure = setup.isEnabled;
                        setup.loading = true;
                        return setup.getSetupData()
                            .then(function() {
                                setup.settingUp = true;
                                setup.loading = false;
                            });
                    };

                    setup.goToMain = function() {
                        setup.settingUp = false;
                    };

                    setup.save = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        setup.isSaving = true;
                        return TwoFactorData.saveSetupData(setup.security_token, setup.setup_data.secret)
                            .then(function(result) {
                                setup.isEnabled = result;
                                if (setup.isEnabled) {
                                    growl.success(LOCALE.maketext("[output,strong,Success:] Two-factor authentication is now configured on your account."));
                                }
                                setup.settingUp = false;
                            })
                            .catch(function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                setup.isSaving = false;
                            });
                    };

                    setup.prompt = function() {
                        var modalInstance = $uibModal.open({
                            templateUrl: "confirm_disable.html",
                            controller: "disablePromptController",
                            controllerAs: "dc",
                            resolve: {
                                users: function() {
                                    return [{ "user_name": setup.setup_data.user }];
                                },
                                mode: function() {
                                    return "disableSelected";
                                }
                            }
                        });

                        return modalInstance.result.then(function(userToRemove) {

                        // the Cancel button will not pass a user
                            if (userToRemove === void 0) {
                                return;
                            }

                            // the Continue button will pass a user, so perform the remove here
                            return TwoFactorData.disableFor(userToRemove)
                                .then(function(result) {

                                // Handle failures
                                    var failures = Object.keys(result.failed);
                                    if (failures.length === 1) {
                                        growl.error(LOCALE.maketext("The system failed to remove two-factor authentication for “[_1]”.", failures[0]));
                                    }

                                    if (result.users_modified.length === 1) {
                                        growl.success(LOCALE.maketext("The system successfully removed two-factor authentication for “[_1]”.", result.users_modified[0]));
                                        setup.isEnabled = false;
                                    }

                                })
                                .catch(function(error) {
                                    growl.error(error);
                                });
                        });
                    };
                }
            ]);

        return controller;
    }
);
