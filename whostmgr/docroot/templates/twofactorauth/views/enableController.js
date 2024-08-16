/*
# templates/twofactorauth/views/enableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                      http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSwitchDirective",
        "app/services/tfaData",
        "cjt/decorators/growlDecorator"
    ],
    function(angular, $, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "enableController",
            ["TwoFactorData", "growl", "growlMessages", "PAGE",
                function(TwoFactorData, growl, growlMessages, PAGE) {

                    var EC = this;

                    EC.tfaEnabled = PARSE.parsePerlBoolean(PAGE.tfa_status);
                    EC.hasRoot = PARSE.parsePerlBoolean(PAGE.has_root);

                    EC.status_check_in_progress = false;
                    EC.changing_status = false;

                    EC.toggle_status = function() {
                        if (!EC.hasRoot || EC.changing_status) {
                            return;
                        }

                        EC.changing_status = true;

                        if (EC.tfaEnabled) {
                            growlMessages.destroyAllMessages();
                            TwoFactorData.disable()
                                .then( function() {
                                    EC.tfaEnabled = false;
                                    growl.success(LOCALE.maketext("The Two-Factor Authentication security policy is now disabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    EC.changing_status = false;
                                });
                        } else {
                            TwoFactorData.enable()
                                .then( function() { // response) {
                                    EC.tfaEnabled = true;
                                    growl.success(LOCALE.maketext("The Two-Factor Authentication security policy is now enabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    EC.changing_status = false;
                                });
                        }
                    };

                    EC.getStatus = function() {
                        if (EC.status_check_in_progress) {
                            return;
                        }
                        EC.status_check_in_progress = true;
                        return TwoFactorData.getStatus()
                            .then( function(results) {
                                if (results !== EC.tfaEnabled) {

                                // this test needs to run only if status has changed
                                    if (results === false) {
                                        growlMessages.destroyAllMessages();
                                    }
                                    growl.warning(LOCALE.maketext("The status for Two-Factor Authentication has changed, possibly in another browser session."));
                                }
                                EC.tfaEnabled = results;
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                EC.status_check_in_progress = false;
                            });
                    };

                    EC.init = function() {
                        $(document).ready(function() {

                        // limit the status polling to root users
                            if (EC.hasRoot) {

                            // for window and tab changes
                                $(window).on("focus", function() {
                                    EC.getStatus();
                                });
                            }
                        });
                    };

                    EC.init();
                }
            ]);

        return controller;
    }
);
