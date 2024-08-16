/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/wizardApi.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService",

        // App components
    ],
    function(angular, _, LOCALE) {
        "use strict";

        var app = angular.module("whm.easyapache4.wizardApi", []);

        app.factory("wizardApi", ["$location", "wizardState", "ea4Data", "ea4Util", function($location, wizardState, ea4Data, ea4Util) {
            var oData = {
                defaultWizardState: {
                    showWizard: false,
                    showSearchAndPage: false,
                    currentStepIndex: 0,
                    showFooter: false,
                    currentStep: "",
                    lastStepName: "",
                    steps: {
                        "mpm": { name: "mpm", title: LOCALE.maketext("Apache [output,acronym,MPM,Multi-Processing Modules]"), path: "mpm", stepIndex: 1, nextStep: "modules" },
                        "modules": { name: "modules", title: LOCALE.maketext("Apache Modules"), path: "modules", stepIndex: 2, nextStep: "php" },
                        "php": { name: "php", title: LOCALE.maketext("[output,acronym,PHP,PHP Hypertext Preprocessor] Versions"), path: "php", stepIndex: 3, nextStep: "extensions" },
                        "extensions": { name: "extensions", title: LOCALE.maketext("[output,acronym,PHP,PHP Hypertext Preprocessor] Extensions"), path: "extensions", stepIndex: 4, nextStep: "ruby" },
                        "ruby": { name: "ruby", title: LOCALE.maketext("[asis,Ruby] via [asis,Passenger]"), path: "ruby", stepIndex: 5, nextStep: "additional" },
                        "additional": { name: "additional", title: LOCALE.maketext("Additional Packages"), path: "additional", stepIndex: 6, nextStep: "review" },
                        "review": { name: "review", title: LOCALE.maketext("Review"), path: "review", stepIndex: 7, nextStep: "" },
                    },
                },
            };

            oData.getDefaultWizardState = function() {
                return oData.defaultWizardState;
            };

            /**
             * Checks the existence of certain packages and keeps or removes certain steps. After
             * the evaluation it rebuilds the wizard steps accordingly.
             * @param {Object} wizardSteps Object containing wizard steps.
             * @param {Object} rebuildArgs
             * @return {Object} Returns the new rebuilt wizardSteps Object.
             */
            oData.rebuildWizardSteps = function(wizardSteps, rebuildArgs) {
                wizardSteps = wizardSteps || {};
                if (!rebuildArgs.rubyPkgsExist) {
                    delete wizardSteps["ruby"];
                }

                if (!rebuildArgs.additionalPkgsExist) {
                    delete wizardSteps["additional"];
                }

                // Sort the steps. orderby isn't working directly in the ng-repeat (shrug).
                var sortedSteps = _.orderBy(_.values(wizardSteps), ["stepIndex"], ["asc"]);
                wizardSteps = _.keyBy(sortedSteps, function(step) {
                    return step.name;
                });
                return wizardSteps;
            };

            oData.init = function() {
                wizardState.steps = oData.defaultWizardState.steps;
                var pkgList = ea4Data.getData("pkgInfoList");
                if (pkgList) {
                    var rebuildArgs = {
                        rubyPkgsExist: ea4Util.doRubyPkgsExist(pkgList),
                        additionalPkgsExist: ea4Data.getData("additionalPkgsExist"),
                    };
                    wizardState.steps = oData.rebuildWizardSteps(oData.defaultWizardState.steps, rebuildArgs);
                }

                wizardState.showWizard = false;
                wizardState.showSearchAndPage = false;
                wizardState.showFooter = false;
                wizardState.currentStepIndex = 1;
                wizardState.lastStepName = "review";
            };

            oData.updateWizard = function(config) {
                _.each(_.keys(config), function(key) {
                    wizardState[key] = config[key];
                });
            };

            oData.getStepByName = function(stepName) {
                return wizardState.steps[stepName];
            };

            oData.getStepNameByIndex = function(index) {
                var stepObj = _.find(wizardState.steps, ["stepIndex", index]);
                if (typeof stepObj !== "undefined") {
                    return stepObj.name;
                }
            };

            /**
             * Reset the wizard to it initial state. It will forward any
             * arguments passed into the call to the registered
             * function.
             *
             * @name reset
             */
            oData.reset = function() {
                wizardState = oData.getDefaultWizardState();
            };

            /**
             * This function auto updates wizardState to the next step index and go to that step
             * if no arguments are passed.
             * If stepName argument is passed, then it updates the wizardState to the given step,
             * and goes to the given step.
             *
             * @name next
             * @arg stepName [optional] If passed, this method will send to the given step's view.
             */
            oData.next = function(stepName) {
                if (stepName) {
                    wizardState.currentStepIndex = oData.getStepByName(stepName).stepIndex;
                    wizardState.currentStep = stepName;
                } else {
                    wizardState.currentStepIndex++;
                    stepName = oData.getNextStepNameByIndex(wizardState.currentStepIndex);
                    wizardState.currentStep = stepName;
                }
                $location.path(stepName);
            };

            oData.getNextStepNameByIndex = function(index) {
                var lastStepIndex = oData.getLastStep().stepIndex;

                var stepObj = _.find(wizardState.steps, ["stepIndex", index]);
                if (typeof stepObj === "undefined") {

                    // Find the next available step.
                    for (var i = index + 1; i <= lastStepIndex; i++) {
                        stepObj = _.find(wizardState.steps, ["stepIndex", i]);
                        if (stepObj === "undefined") {
                            continue;
                        }
                    }
                }
                return (stepObj) ? stepObj.name : "";
            };

            /**
             * Get the wizard's last step object.
             * @return {Object} Returns wizard step object.
             */
            oData.getLastStep = function() {
                return wizardState.steps[wizardState.lastStepName];
            };

            return {
                init: oData.init,
                getStepByName: oData.getStepByName,
                updateWizard: oData.updateWizard,
                next: oData.next,
                getDefaultWizardState: oData.getDefaultWizardState,
                reset: oData.reset,
                rebuildWizardSteps: oData.rebuildWizardSteps,
                getLastStep: oData.getLastStep,
                getNextStepNameByIndex: oData.getNextStepNameByIndex,
            };
        }]);
    }
);
