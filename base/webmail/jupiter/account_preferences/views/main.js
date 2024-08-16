/*
# cpanel - base/webmail/jupiter/account_preferences/views/main.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/accountPrefs",
        "cjt/modules",
        "cjt/services/alertService",
        "cjt/directives/toggleSwitchDirective",
        "cjt/directives/toggleLabelInfoDirective",
    ],
    function(angular, _, LOCALE, AccountPrefsService) {

        "use strict";

        var initialLoadVariable = "MAILBOX_AUTOCREATION_ENABLED";
        var MODULE_NAMESPACE = "webmail.accountPrefs.views.main";
        var TEMPLATE_URL = "views/main.ptt";
        var MODULE_DEPENDANCIES = [];

        var CONTROLLER_INJECTABLES = ["$scope", AccountPrefsService.serviceName, "alertService", initialLoadVariable, "RESOURCE_TEMPLATE", "EMAIL_ADDRESS", "DISPLAY_EMAIL_ADDRESS"];
        var CONTROLLER_NAME = "MainController";
        var CONTROLLER = function AccountPreferencesMainController($scope, $service, $alertService, mailboxAutoCreationEnabled, RESOURCE_TEMPLATE, email, displayEmailAddress) {
            $scope.email = email;
            $scope.displayEmailAddress = _.escape(displayEmailAddress);
            $scope.examplePlusAddress = $scope.displayEmailAddress.split("@").join("+plusaddress@");

            $scope.resourcesPanelTemplate = RESOURCE_TEMPLATE;
            $scope.mailboxAutoCreationEnabled = mailboxAutoCreationEnabled;

            /**
             * Enable Auto Folder Creation (Plus Addressing)
             *
             * @returns {Promise} update service promise
             */
            $scope.enableMailboxAutoCreate = function enableMailboxAutoCreate() {
                var onSuccess = $alertService.success.bind($alertService, LOCALE.maketext("You enabled automatic folder creation for “[_1]”.", $scope.displayEmailAddress));
                var onError = $alertService.add.bind($alertService, {
                    type: "danger",
                    message: LOCALE.maketext("The system could not enable automatic folder creation for “[_1]”.", $scope.displayEmailAddress),
                });
                return $service.enableMailboxAutoCreate($scope.email).then(onSuccess, onError);
            };

            /**
             * Disable Auto Folder Creation (Plus Addressing)
             *
             * @returns {Promise} update service promise
             */
            $scope.disableMailboxAutoCreate = function disableMailboxAutoCreate() {
                var onSuccess = $alertService.success.bind($alertService, LOCALE.maketext("You disabled automatic folder creation for “[_1]”.", $scope.displayEmailAddress));
                var onError = $alertService.add.bind($alertService, {
                    type: "danger",
                    message: LOCALE.maketext("The system could not disable automatic folder creation for “[_1]”.", $scope.displayEmailAddress),
                });
                return $service.disableMailboxAutoCreate($scope.email).then(onSuccess, onError);
            };

            /**
             * Toggle Whether Auto Folder Creation (Plus Addressing) is enabled
             *
             * @returns {Promise} update service promise
             */
            $scope.toggleAutoFolderCreation = function toggleAutoFolderCreation() {
                $scope.mailboxAutoCreationEnabled = !$scope.mailboxAutoCreationEnabled;
                return $scope.mailboxAutoCreationEnabled ? $scope.enableMailboxAutoCreate() : $scope.disableMailboxAutoCreate();
            };

        };

        var app = angular.module(MODULE_NAMESPACE, MODULE_DEPENDANCIES);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES.concat(CONTROLLER));

        var resolver = {};
        resolver[initialLoadVariable] = [
            AccountPrefsService.serviceName,
            "EMAIL_ADDRESS",
            function($service, EMAIL_ADDRESS) {
                return $service.isMailboxAutoCreateEnabled(EMAIL_ADDRESS);
            },
        ];

        return {
            "controller": CONTROLLER_NAME,
            "class": CONTROLLER,
            "template": TEMPLATE_URL,
            "namespace": MODULE_NAMESPACE,
            "resolver": resolver,
        };
    }
);
