/*
# views/conversion_detail.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/conversion_history"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "conversionDetailController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConversionHistory", "$timeout",
                function($anchorScroll, $location, $routeParams, growl, ConversionHistory, $timeout) {

                    var detail = this;

                    detail.loading = true;

                    detail.jobId = 0;

                    detail.conversionData = {};
                    detail.progressBarType = "info";
                    detail.currentProgressMessage = "";

                    detail.splitWarnings = function(warnings) {
                        if (warnings) {
                            return warnings.split("\n");
                        }
                        return null;
                    };

                    detail.viewHistory = function() {
                        $location.path("/history/");
                    };

                    detail.viewAddons = function() {
                        $location.path("/main");
                    };

                    detail.updateSteps = function() {
                        return ConversionHistory.getDetails(detail.jobId, detail.currentStep)
                            .then(
                                function(result) {

                                    // check to see if local copy of conversion data is
                                    // populated. if not, put the results of the getDatails
                                    // call there
                                    if (!detail.conversionData.hasOwnProperty("domain")) {

                                        // make a local copy of the data so the
                                        // ui is properly synchronized
                                        for (var prop in result) {

                                            if (result.hasOwnProperty(prop)) {
                                                if (prop === "steps") {
                                                    continue;
                                                }
                                                detail.conversionData[prop] = result[prop];
                                            }
                                        }

                                        detail.conversionData.steps = result.steps.slice();

                                        if (detail.conversionData.job_status === "INPROGRESS") {
                                            detail.currentProgressMessage = detail.conversionData.steps[detail.conversionData.steps.length - 1].step_name;
                                            detail.progressBarType = "info";
                                            return $timeout(function() {
                                                return detail.updateSteps();
                                            }, 2000);
                                        } else if (detail.conversionData.job_status === "DONE") {
                                            detail.currentProgressMessage = LOCALE.maketext("Conversion Completed");
                                            detail.progressBarType = "success";
                                        } else {
                                            detail.currentProgressMessage = LOCALE.maketext("Conversion Failed");
                                            detail.progressBarType = "danger";
                                        }
                                    } else { // otherwise, add any new steps to the local copy

                                        // if the current list of steps is shorter than the new list
                                        // add the new steps to the end of the list
                                        var currentStepCount = detail.conversionData.steps.length;
                                        var newStepCount = result.steps.length;

                                        if ( currentStepCount < newStepCount) {

                                            // update last step with new status and warnings, if any
                                            detail.conversionData.steps[currentStepCount - 1].status = result.steps[currentStepCount - 1].status;
                                            if (result.steps[currentStepCount - 1].warnings) {
                                                detail.conversionData.steps[currentStepCount - 1].warnings = result.steps[currentStepCount - 1].warnings;
                                            }

                                            // add any new steps after the updated last step
                                            var newSteps = result.steps.slice(currentStepCount);
                                            detail.conversionData.steps = detail.conversionData.steps.concat(newSteps);

                                            // update the status message to the new last step name
                                            if (result.job_status === "FAILED") {
                                                detail.progressBarType = "danger";
                                            } else if (result.job_status === "DONE") {
                                                detail.progressBarType = "success";
                                            } else {
                                                detail.progressBarType = "info";
                                            }

                                            detail.currentProgressMessage = detail.conversionData.steps[detail.conversionData.steps.length - 1].step_name;
                                        }

                                        if (!result.job_end_time || result.steps[newStepCount - 1].status === "INPROGRESS") {

                                            // still in progress--schedule the next check
                                            // schedule at least one final check in any case
                                            return $timeout(function() {
                                                return detail.updateSteps();
                                            }, 2000);
                                        } else {
                                            detail.conversionData.job_status = result.job_status;
                                            detail.conversionData.job_end_time = result.job_end_time;

                                            if (detail.conversionData.job_status === "DONE") {
                                                detail.currentProgressMessage = LOCALE.maketext("Conversion Completed");
                                                detail.progressBarType = "success";
                                            } else if (detail.conversionData.job_status === "FAILED") {
                                                detail.currentProgressMessage = LOCALE.maketext("Conversion Failed");
                                                detail.progressBarType = "danger";
                                            }
                                        }
                                    }

                                }, function(error) {
                                    growl.error(error);
                                }
                            );
                    };

                    detail.load = function() {
                        detail.loading = true;
                        detail.updateSteps()
                            .finally(
                                function() {
                                    detail.loading = false;
                                }
                            );
                    };

                    detail.goToHistory = function() {
                        return $location.path("/history");
                    };

                    detail.init = function() {
                        detail.jobId = $routeParams.jobid;
                        detail.load();
                    };

                    detail.init();
                }
            ]);

        return controller;
    }
);
