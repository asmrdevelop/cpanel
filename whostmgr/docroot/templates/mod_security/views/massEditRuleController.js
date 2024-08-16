/*
# templates/mod_security/views/massEditRuleController.js Copyright(c) 2020 cPanel, L.L.C.
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
        "jquery",
        "cjt/jquery/plugins/rangeSelection",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "massEditRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "$q", "$timeout", "ruleService", "alertService", "spinnerAPI", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, $q, $timeout, ruleService, alertService, spinnerAPI, PAGE) {

                    // CONSTANTS
                    var ANIMATION_INTER_STEP_DELAY = 500; // in milliseconds.

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        return $scope.cantEdit || form.txtRules.$pristine || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = true;
                        $scope.rules = "";
                        $scope.deploy = false;
                        $scope.clearNotices();
                        $scope.cantEdit = false;
                    };

                    /**
                 * Clear the notices
                 *
                 * @method clearNotices
                 */
                    $scope.clearNotices = function() {
                        alertService.clear();
                        $scope.notice = "";
                    };

                    /**
                 * Navigate to the previous view.
                 *
                 * @method  cancel
                 */
                    $scope.cancel = function() {
                        $scope.clearNotices();
                        $scope.loadView("rulesList");
                    };

                    /**
                 * Save the form and navigate or clean depending on the users choices.
                 *
                 * @method save
                 * @param  {FormController} form
                 * @return {Promise}
                 */
                    $scope.save = function(form) {
                        $scope.clearNotices();

                        if (!form.$valid) {
                            return;
                        }

                        spinnerAPI.start("loadingSpinner");
                        $scope.progress = 0;
                        $scope.cantEdit = true;
                        return ruleService
                            .setCustomConfigText($scope.rules, $scope.deploy)
                            .then(function() {

                                // on success, update alert and load the view
                                spinnerAPI.stop("loadingSpinner");
                                $timeout(function() {
                                    $scope.progress = 100;
                                    $timeout(function() {

                                        // success
                                        if ($scope.deploy) {
                                            alertService.add({
                                                type: "success",
                                                message: LOCALE.maketext("You have successfully saved and deployed your [asis,ModSecurity™] rules."),
                                                id: "alertSaveSuccess",
                                            });
                                        } else {
                                            alertService.add({
                                                type: "success",
                                                message: LOCALE.maketext("You have successfully saved your [asis,ModSecurity™] rules."),
                                                id: "alertSaveSuccess",
                                            });
                                        }

                                        $timeout(function() {
                                            $scope.loadView("rulesList");
                                            $scope.showProgress = false;
                                        }, 2 * ANIMATION_INTER_STEP_DELAY);
                                    }, 2 * ANIMATION_INTER_STEP_DELAY);
                                }, 2 * ANIMATION_INTER_STEP_DELAY);
                            }, function(error) {
                                spinnerAPI.stop("loadingSpinner");
                                $scope.cantEdit = false;
                                if (error) {

                                    // failures like timeout, lost connection, etc.
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        id: "errorFetchRules",
                                    });
                                }

                                // ensure the any notifications and/or the final error is in view and focus is in the rule field
                                $timeout(function() {
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRules").focus();
                                }, 2 * ANIMATION_INTER_STEP_DELAY);

                            }, function(data) {

                                switch (data.type) {
                                    case "post":

                                        // Only show the progress if there are more then 2 pages
                                        if (data.totalPages > 2) {
                                            $scope.showProgress = true;
                                        }

                                        // Update the progress
                                        $scope.progress = Math.floor(data.page / data.totalPages * 100);
                                        break;
                                    case "error":

                                        // api related failures.
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(data.error),
                                            id: "errorSaveRules",
                                        });
                                        break;
                                }
                            });
                    };

                    /**
                 * Fetch the config text from the user defined rules file
                 * @return {Promise} Promise that will fulfill the request.
                 */
                    var fetchRules = function() {
                        spinnerAPI.start("loadingSpinner");
                        $scope.progress = 0;
                        $scope.cantEdit = true;
                        return ruleService
                            .getCustomConfigText()
                            .then(angular.noop, function(error) {
                                if (error) {

                                    // failures like timeout, lost connection, etc.
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error),
                                        id: "errorFetchRules",
                                    });
                                }
                            }, function(data) {
                                switch (data.type) {
                                    case "page":

                                        // Only show the progress if there are more then 2 pages
                                        if (data.totalPages > 2) {
                                            $scope.showProgress = true;
                                        }

                                        if (data.text) {

                                            // Update the progress
                                            $scope.progress = Math.floor(data.page / data.totalPages * 100);

                                            // Append
                                            $scope.rules += data.text.join("");
                                        }
                                        break;
                                    case "error":

                                        // api related failures.
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(data.error),
                                            id: "errorFetchRules",
                                        });
                                        break;
                                }
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                                $timeout(function() {
                                    $scope.progress = 100;
                                    $timeout(function() {

                                        // delayed for a little so the progress bar can finish
                                        $scope.cantEdit = false;
                                        $scope.showProgress = false;
                                        $timeout(function() {
                                            $scope.progress = 0;
                                            angular.element(document.querySelector( "#txtRules" )).selectRange(0);
                                        }, ANIMATION_INTER_STEP_DELAY);
                                    }, ANIMATION_INTER_STEP_DELAY);
                                }, ANIMATION_INTER_STEP_DELAY);

                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.showProgress = false;
                    $scope.cantEdit = true;
                    $scope.clearForm();
                    fetchRules();
                },
            ]);

        return controller;
    }
);
