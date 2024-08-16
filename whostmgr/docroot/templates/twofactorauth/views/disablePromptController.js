/*
# twofactorauth/views/disablePromptController.js   Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "uiBootstrap"
    ],
    function(angular, $, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "disablePromptController",
            ["$scope", "$uibModalInstance", "users", "mode",
                function($scope, $uibModalInstance, users, mode) {

                    var DCC = this;

                    DCC.users = users;
                    DCC.mode = mode;

                    DCC.cancelDisable = function() {
                        $uibModalInstance.close();
                    };

                    DCC.disableConfirmationMessage = function() {
                        if (DCC.mode === "disableSelected") {
                            if (DCC.users.length === 1) {
                                return LOCALE.maketext("Are you sure you want to remove two-factor authentication for “[_1]”?", DCC.users[0].user_name);
                            } else if (DCC.users.length > 1) {
                                return LOCALE.maketext("Are you sure you want to remove two-factor authentication for [quant,_1,user,users]?", DCC.users.length);
                            }
                        }
                        return LOCALE.maketext("Do you want to remove two-factor authentication for all users?");
                    };

                    DCC.disableTFAFor = function() {
                        $uibModalInstance.close(DCC.users, DCC.mode);
                    };
                }]);

        return controller;
    }
);
