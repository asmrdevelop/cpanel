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
            "editRuleController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "spinnerAPI", "alertService", "ruleService", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, spinnerAPI, alertService, ruleService, PAGE) {

                    /**
                 * Disable the save button based on form state
                 *
                 * @method disableSave
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        var pristineInputs = form.rule.$pristine && form.enabled.$pristine;
                        return ($scope.isEditor && $scope.cantEdit) || pristineInputs || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Clear the form
                 *
                 * @method clearForm
                 */
                    $scope.clearForm = function() {
                        $scope.enabled = false;
                        $scope.oldRule = 0;
                        $scope.ruleText = "";
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
                        $scope.loadView(backRoute);
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
                            .updateRule($scope.configFile, $scope.id, $scope.rule, $scope.enabled, $scope.enabled !== $scope.originalEnabled, $scope.deploy)
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
                                        message: LOCALE.maketext("You have successfully updated the [asis,ModSecurity™] rule."),
                                        id: "alertAddSuccess",
                                        replace: true,
                                    });

                                    app.firstLoad.rules = false;
                                    $scope.loadView("rulesList");
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
                            ).then(
                                function finish() {
                                    spinnerAPI.stop("loadingSpinner");
                                }
                            );
                    };

                    /**
                 * Fetch the list of hits from the server
                 *
                 * @method fetchRule
                 * @param {Number} ruleId       The numeric ID of the rule.
                 * @param {String} [vendorId]   Optional unique vendor ID string. If this is not
                 *                              included, we will search for the rule in the user
                 *                              defined rule set.
                 * @return {Promise}            Promise that when fulfilled with contain the matching
                 *                              rules, only one if the file isn't messed up with
                 *                              duplicate id's. Defensive logic is in place for other
                 *                              conditions. > 1 match and no matches.
                 */
                    var fetchRule = function(ruleId, vendorId) {
                        spinnerAPI.start("loadingSpinner");
                        return ruleService
                            .fetchRulesById(ruleId, vendorId)
                            .then(function(results) {

                                // May be useful
                                $scope.stagedChanges = results.stagedChanges;
                                var matchedRule = results.items[0];
                                $scope.id = matchedRule.id;
                                $scope.enabled = !PARSE.parsePerlBoolean(matchedRule.disabled);
                                $scope.originalEnabled = $scope.enabled;
                                $scope.meta_msg = matchedRule.meta_msg;
                                $scope.rule = matchedRule.rule;
                                $scope.cantEdit = false;
                                $scope.configFile = matchedRule.config;

                                // If the vendor or config isn't active, we should let the user know
                                if (matchedRule.vendor_id && (!matchedRule.vendor_active || !matchedRule.config_active)) {
                                    var message = !matchedRule.vendor_active ?
                                        LOCALE.maketext("The vendor that provides the rule “[_1]” is disabled. Whether enabled or disabled, the rule will have no visible effect until you enable that vendor.", matchedRule.vendor_id) :
                                        LOCALE.maketext("The configuration file that provides the rule “[_1]” is disabled. Whether enabled or disabled, the rule will have no visible effect until you enable the configuration file for the “[_2]” vendor.", matchedRule.config, matchedRule.vendor_id);

                                    alertService.add({
                                        type: "warning",
                                        message: message,
                                        id: "alertDisabledWarning",
                                        replace: false,
                                    });
                                }

                            }, function(error) {
                                var message;
                                if (error.count > 1) {
                                    message = vendorId ?
                                        LOCALE.maketext("The rule with ID number “[_1]” is not unique. There are multiple rules that use the same ID number within the “[_2]” vendor rule set.", ruleId, vendorId) :
                                        LOCALE.maketext("The rule with ID number “[_1]” is not unique. There are multiple rules that use the same ID number within your user-defined rule set.", ruleId);

                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(message),
                                        id: "alertEditError",
                                    });
                                } else if (error.count < 1) {
                                    message = vendorId ?
                                        LOCALE.maketext("The system could not find the rule with ID number “[_1]” from the “[_2]” vendor rule set.", ruleId, vendorId) :
                                        LOCALE.maketext("The system could not find the rule with ID number “[_1]” from your user-defined rule set.", ruleId);

                                    alertService.add({
                                        type: "warning",
                                        message: _.escape(message),
                                        id: "alertEditWarning",
                                    });
                                } else {
                                    alertService.add({
                                        type: "danger",
                                        message: _.escape(error.message),
                                        id: "errorFetchRulesList",
                                    });
                                }

                                $scope.cantEdit = true;
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                    };

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {
                        $scope.loadView("hitList");
                    }

                    // Initialize the form on first load.
                    $scope.isVendor = !!$routeParams.vendorId;
                    $scope.isEditor = true;
                    $scope.cantEdit = true;
                    $scope.clearForm();

                    var ruleId = $routeParams["ruleId"];
                    var vendorId = $routeParams["vendorId"];
                    var backRoute = $routeParams["back"];
                    if (!backRoute) {
                        backRoute = "rulesList";
                    }

                    if (angular.isUndefined(ruleId)) {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system could not find the ID number for this rule."),
                            id: "alertNoIdError",
                        });
                        $scope.cantEdit = true;
                    } else {

                        // Let the user know that they can only toggle it on or off if it's a vendor rule
                        if ($scope.isVendor) {
                            alertService.add({
                                type: "info",
                                message: LOCALE.maketext("A vendor configuration file provides this rule. You cannot edit vendor rules. You can enable or disable this rule with the controls below."),
                                id: "alertVendorRuleInfo",
                            });
                        }
                        fetchRule(ruleId, vendorId);
                    }

                },
            ]);

        return controller;
    }
);
