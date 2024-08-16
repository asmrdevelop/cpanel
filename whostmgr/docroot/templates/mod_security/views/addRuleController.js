/*
# templates/mod_security/views/addRuleController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
    ],
    function(angular, _, $, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "$q", "spinnerAPI", "alertService", "ruleService", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, $q, spinnerAPI, alertService, ruleService, PAGE) {

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        return (form.rule.$pristine && form.enabled.$pristine) || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = true;
                        $scope.rule = "";
                        $scope.deploy = false;
                        $scope.clearNotices();
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
                 * @param  {Boolean} exit If true, will navigate back on completion, if false,
                 * will clear the form and let you add another rule.
                 * @return {Promise}
                 */
                    $scope.save = function(form, exit) {
                        $scope.clearNotices();

                        if (!form.$valid) {
                            return;
                        }

                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .addRule($scope.rule, $scope.enabled, $scope.deploy)
                            .then(

                                /**
                                 * Handle successfully adding the rule
                                 * @method success
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function success(rule) {
                                    $scope.clearNotices();
                                    form.$setPristine();
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.clearForm();

                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You have successfully saved your [asis,ModSecurity™] rule with the following ID: [_1].", _.escape(rule.id)),
                                        id: "alertAddSuccess",
                                        replace: true,
                                    });

                                    if (exit) {
                                        $scope.loadView("rulesList");
                                    } else {

                                        if ( $scope.isCopy ) {
                                            $scope.getClonedRule(rule);
                                        }

                                        // refocus the user for the next add
                                        $scope.scrollTo("top");
                                        document.getElementById("txtRuleText").focus();
                                    }
                                },

                                /**
                                 * Handle failure of adding the rule
                                 * @method failure
                                 * @private
                                 * @param  {Object} error Error from the backend.
                                 *   @param {String} message
                                 *   @param {Boolean} duplicate true if this is a duplicate queue item, false otherwise.
                                 */
                                function failure(error) {
                                    $scope.notice = "";
                                    if (error && error.duplicate) {
                                        alertService.add({
                                            type: "warning",
                                            message: LOCALE.maketext("There is a duplicate [asis,ModSecurity™] rule in the staged configuration file. You cannot add a duplicate rule."),
                                            id: "alertAddWarning",
                                        });
                                    } else {
                                        var message = error.message || error; // It can come from either structured or unstructured errors
                                        alertService.add({
                                            type: "danger",
                                            message: _.escape(message),
                                            id: "alertAddFailure",
                                        });
                                    }

                                    // ensure the error is in view and focus is in the rule field
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRuleText").focus();
                                },

                                /**
                                 * Handle step wise updating
                                 * @method notify
                                 * @private
                                 * @param  {Rule} rule Rule added to the system
                                 */
                                function notify(notice) {
                                    $scope.notice += notice + "\n";
                                }
                            ).finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    /**
                 * Disable the rule that
                 *
                 * @method disableOriginalRule
                 * @param  {object}  rule            The original rule to be disabled
                 * @param  {string}  rule.id         The id of the original rule
                 * @param  {string}  rule.config     The configuration file of the original file
                 * @param  {Boolean} rule.disabled   Is the rule disabled?
                 * @return {Promise}
                 */
                    $scope.disableOriginalRule = function(rule) {
                        return ruleService
                            .disableRule(rule.config, rule.id, false)
                            .then(

                                /**
                                 * Handle successfully disabling the original rule
                                 * @method success
                                 * @private
                                 */
                                function success() {
                                    rule.disabled = true;
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully disabled the [asis,ModSecurity™] rule with the following ID: [_1]", _.escape(rule.id)),
                                        id: "alertDisableSuccess",
                                    });
                                },

                                /**
                                 * Handle failure of cloning the rule
                                 * @method failure
                                 * @private
                                 * @param  {Object} error Error from the backend.
                                 *   @param {String} message
                                 */
                                function failure(error) {
                                    var message = error.message || error;
                                    alertService.add({
                                        type: "danger",
                                        message: message,
                                        id: "alertDisableFailure",
                                    });
                                }
                            ).finally(function() {

                                // ensure the alert is in view and focus is in the rule field
                                $scope.scrollTo("top");
                                document.getElementById("txtRuleText").focus();
                            });
                    };

                    /**
                 * Retrieve a copy of the rule with a unique id
                 *
                 * @method getClonedRule
                 * @param  {object}  rule            The original rule to be cloned
                 * @param  {string}  rule.id         The id of the original rule
                 * @param  {string}  rule.config     The configuration file of the original file
                 * @param  {Boolean} rule.disabled   Is the rule disabled?
                 * @return {Promise}
                 */
                    $scope.getClonedRule = function(rule) {
                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .cloneRule(rule.id, rule.config)
                            .then(

                                /**
                                 * Handle successfully cloning the rule
                                 * @method success
                                 * @private
                                 * @param  {Rule} rule The cloned rule with a unique id ready to be saved
                                 */
                                function success(rule) {
                                    $scope.id = rule.id;
                                    $scope.enabled = !rule.disabled;
                                    $scope.rule = rule.rule;

                                    // activate the save buttons
                                    $scope.form.rule.$pristine = false;
                                },

                                /**
                                 * Handle failure of cloning the rule
                                 * @method failure
                                 * @private
                                 * @param {Object} error           Error from the backend.
                                 * @param {String} error.message   The error message.
                                 */
                                function failure(error) {
                                    var message = error.message || error;
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(message),
                                        id: "alertCopyFailure",
                                    });

                                    // ensure the error is in view and focus is in the rule field
                                    $scope.scrollTo("top");
                                    document.getElementById("txtRuleText").focus();
                                }
                            ).finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.clearForm();

                    // check for copy of existing rule
                    if ( $location.$$path.indexOf("copy") !== -1 ) {
                        $scope.originalRule = {
                            id: $routeParams["id"],
                            config: $routeParams["config"],
                            disabled: $routeParams["disabled"],
                        };
                        if ( $scope.originalRule.id && $scope.originalRule.config ) {
                            $scope.isCopy = true;
                            $scope.getClonedRule($scope.originalRule);
                        }
                    }
                },
            ]);

        return controller;
    }
);
