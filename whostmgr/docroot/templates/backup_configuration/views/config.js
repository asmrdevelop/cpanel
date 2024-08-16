/*
# backup_configuration/views/config.js             Copyright 2022 cPanel, L.L.C.
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
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/username-validators",
        "cjt/validator/compare-validators",
        "app/services/backupConfigurationServices"
    ],
    function(angular, _, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        // var table = new Table();

        var controller = app.controller(
            "config", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$q",
                "$window",
                "backupConfigurationServices",
                "alertService",
                "$timeout",

                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $q,
                    $window,
                    backupConfigurationServices,
                    alertService,
                    $timeout) {

                    /**
                     * Make a copy of the source backup configuration
                     * and return a reference to it.
                     *
                     * @function cloneConfiguration
                     * @param  {Object} sourceConfig - configuration object to copy
                     * @return {Object} - reference to new copy
                     */
                    var cloneConfiguration = function(sourceConfig) {

                        // first do a shallow copy of the sourceConfig
                        var copyOfConfig = _.clone(sourceConfig);

                        // special case properties not copied by shallow copy
                        if (sourceConfig.hasOwnProperty("backupdays")) {
                            copyOfConfig.backupdays = _.clone(sourceConfig.backupdays);
                        }
                        if (sourceConfig.hasOwnProperty("backup_monthly_dates")) {
                            copyOfConfig.backup_monthly_dates = _.clone(sourceConfig.backup_monthly_dates);
                        }

                        return copyOfConfig;
                    };

                    /**
                     * Fetches current backup configuration.
                     *
                     * @scope
                     * @method getBackupConfiguration
                     */
                    $scope.getBackupConfiguration = function() {
                        alertService.clear();
                        backupConfigurationServices.getBackupConfig()
                            .then(function(configuration) {
                                if (!$scope.initialFormData) {
                                    $scope.formData = cloneConfiguration(configuration);
                                    $scope.initialFormData = cloneConfiguration(configuration);
                                } else {
                                    $scope.formData = cloneConfiguration(configuration);
                                }
                                $scope.backupConfigLoaded = true;
                                $scope.formEnabled = $scope.formData.backupenable;
                                $scope.setMonthlyBackupDays();
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "configuration-loading-error",
                                    closeable: true
                                });

                                // set to true on error so loading dialog is removed
                                $scope.backupConfigLoaded = true;
                            });
                    };

                    /**
                     * Toggle between percent and MB as units of storage
                     *
                     * @scope
                     * @method handleUnitToggle
                     * @param  {String} value - value to toggle
                     */
                    $scope.handleUnitToggle = function(value) {
                        if (value === "%") {
                            $scope.formData.min_free_space_unit = "percent";
                        } else if (value === "MB") {
                            $scope.formData.min_free_space_unit = "MB";
                        } else {
                            throw "DEVELOPER ERROR: value argument has unexpected value: " + value;
                        }
                    };

                    /**
                     * Add or remove day from list of active backup days
                     *
                     * @scope
                     * @method handleDaysToggle
                     * @param  {Number} index - index of toggled day in array of days
                     * @param {FormController} form - the form calling the function
                     */
                    $scope.handleDaysToggle = function(index, form) {
                        if ($scope.formData.backupdays[index]) {
                            delete $scope.formData.backupdays[index];
                        } else {
                            $scope.formData.backupdays[index] = index.toString();
                        }

                        form.$setDirty();

                        // if length of array is zero no days are selected and
                        // warning is displayed
                        $scope.selectedDays = Object.keys($scope.formData.backupdays);
                    };

                    /*
                     * Handles toggle between days when setting weekly backups
                     *
                     * @scope
                     * @method handleDayToggle
                     * @param  {Number} index - index referencing active backup day in
                     * @param {FormController} form - the form calling the function
                     * weekly backup settings
                     */

                    $scope.handleDayToggle = function(index, form) {
                        $scope.formData.backup_weekly_day = index;
                        form.$setDirty();
                    };

                    /**
                     * Handles toggle of monthly backup schedule options
                     *
                     * @scope
                     * @method handleMonthlyToggle
                     * @param  {String} day - day to toggle
                     */
                    $scope.handleMonthlyToggle = function(day) {
                        if (!$scope.formData.backup_monthly_dates) {
                            $scope.formData.backup_monthly_dates = {};
                        }

                        if (day === "first") {
                            if ($scope.formData.backup_monthly_dates[1]) {
                                delete $scope.formData.backup_monthly_dates[1];
                            } else {
                                $scope.formData.backup_monthly_dates[1] = "1";
                            }
                        } else if (day === "fifteenth") {
                            if ($scope.formData.backup_monthly_dates[15]) {
                                delete $scope.formData.backup_monthly_dates[15];
                            } else {
                                $scope.formData.backup_monthly_dates[15] = "15";
                            }
                        } else {
                            throw "DEVELOPER ERROR: value argument has unexpected value: " + day;
                        }
                        $scope.setMonthlyBackupDays();
                    };

                    /**
                     * Set boolean values for monthly dates object based on active
                     * backup days
                     *
                     * @scope
                     * @method setMonthlyBackupDays
                     */
                    $scope.setMonthlyBackupDays = function() {
                        if (!$scope.monthlyBackupBool) {
                            $scope.monthlyBackupBool = {};
                        }

                        if ($scope.formData.backup_monthly_dates[1]) {
                            $scope.monthlyBackupBool["first"] = true;
                        } else {
                            $scope.monthlyBackupBool["first"] = false;
                        }

                        if ($scope.formData.backup_monthly_dates[15]) {
                            $scope.monthlyBackupBool["fifteenth"] = true;

                        } else {
                            $scope.monthlyBackupBool["fifteenth"] = false;
                        }

                        if (!$scope.monthlyBackupBool["first"] && !$scope.monthlyBackupBool["fifteenth"]) {
                            delete $scope.formData.backup_monthly_dates;
                        }
                    };

                    /**
                     * Opens new tab with select user options
                     *
                     * @scope
                     * @method redirectToSelectUsers
                     */
                    $scope.redirectToSelectUsers = function() {
                        window.open("../backup_user_selection");
                    };

                    /**
                     * Saves a new backup configuration via API
                     *
                     * @scope
                     * @param {FormController} form - the form calling the function
                     * @method saveConfiguration
                     */
                    $scope.saveConfiguration = function(form) {
                        $scope.saving = true;
                        return backupConfigurationServices.setBackupConfig($scope.formData)
                            .then(function(success) {
                                $scope.initialFormData = cloneConfiguration($scope.formData);
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    message: LOCALE.maketext("The system successfully saved the backup configuration."),
                                    id: "save-configuration-succeeded"
                                });

                                // on success force form to clean state
                                form.$setPristine();
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "save-configuration-failed"
                                });
                            })
                            .finally(function() {
                                $scope.saving = false;
                            });
                    };

                    /**
                     * Resets config page to initial values and scrolls to top of page
                     *
                     * @scope
                     * @method resetConfiguration
                     * @param {FormController} form - the form calling the function
                     */
                    $scope.resetConfiguration = function(form) {

                        $scope.formData = cloneConfiguration($scope.initialFormData);

                        // disable form controls if backups are disabled
                        $scope.enableBackupConfig();

                        // update selectedDays array so validation message is correctly displayed
                        $scope.selectedDays = Object.keys($scope.formData.backupdays);

                        // massage monthly backup days checkboxes
                        $scope.setMonthlyBackupDays();
                        form.$setPristine();

                        $location.hash("backup_status");
                        $anchorScroll();
                    };

                    /**
                     * Handles backup enable toggle and sets scope property to remove
                     * focus from all inputs if backup is not enabled
                     *
                     * @scope
                     * @method enableBackupConfig
                     */
                    $scope.enableBackupConfig = function() {
                        if (!$scope.formData.backupenable) {
                            $scope.formEnabled = false;
                        } else {
                            $scope.formEnabled = true;
                        }
                    };

                    /**
                     * Prevent typing of decimal points (periods) in field
                     *
                     * @scope
                     * @method noDecimalPoints
                     * @param {keyEvent} key event associated with key down
                     */

                    $scope.noDecimalPoints = function(keyEvent) {

                        // keyEvent is jQuery wrapper for KeyboardEvent
                        // better to look at properties in wrapped event
                        var actualEvent = keyEvent.originalEvent;

                        // future proofing: "key" is better property to use
                        // but is not completely supported
                        if ((actualEvent.hasOwnProperty("key") && actualEvent.key === ".") ||
                            (actualEvent.keyCode === 190)) {
                            keyEvent.preventDefault();
                        }
                    };

                    /**
                     * Prevent pasting of non-numbers in field
                     *
                     * @scope
                     * @method onlyNumbers
                     * @param {clipboardEvent} clipboard event associated with paste
                     */

                    $scope.onlyNumbers = function(pasteEvent) {
                        var pastedData = pasteEvent.originalEvent.clipboardData.getData("text");

                        if (!pastedData.match(/[0-9]+/)) {
                            pasteEvent.preventDefault();
                        }
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.backupConfigLoaded = false;

                        $scope.getBackupConfiguration();

                        $scope.dailyDays = [
                            LOCALE.maketext("Sunday"),
                            LOCALE.maketext("Monday"),
                            LOCALE.maketext("Tuesday"),
                            LOCALE.maketext("Wednesday"),
                            LOCALE.maketext("Thursday"),
                            LOCALE.maketext("Friday"),
                            LOCALE.maketext("Saturday")
                        ];
                        $scope.weeklyDays = [
                            LOCALE.maketext("Sunday"),
                            LOCALE.maketext("Monday"),
                            LOCALE.maketext("Tuesday"),
                            LOCALE.maketext("Wednesday"),
                            LOCALE.maketext("Thursday"),
                            LOCALE.maketext("Friday"),
                            LOCALE.maketext("Saturday")
                        ];
                        $scope.absolutePathRegEx = /^\/./;
                        $scope.relativePathRegEx = /^\w./;
                        $scope.remoteHostValidation = /^[a-z0-9.-]{1,}$/i;
                        $scope.remoteHostLoopbackValue = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
                        $scope.disallowedPathChars = /[\\?%*:|"<>]/g;

                        $scope.validating = false;
                        $scope.toggled = true;
                        $scope.saving = false;
                        $scope.deleting = false;
                        $scope.updating = false;
                        $scope.showDeleteConfirmation = false;
                        $scope.destinationName = "";
                        $scope.destinationId = "";
                        $scope.activeTab = 0;
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
