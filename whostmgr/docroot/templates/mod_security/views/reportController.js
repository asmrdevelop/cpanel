/*
# templates/mod_security/views/reportController.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                             All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define([
    "angular",
    "cjt/util/locale",
    "uiBootstrap",
    "app/services/reportService",
    "cjt/validator/email-validator",
    "cjt/directives/validationContainerDirective",
    "cjt/directives/validationItemDirective",
    "cjt/directives/spinnerDirective",
    "cjt/filters/wrapFilter",
    "cjt/filters/breakFilter",
],
function(angular, LOCALE) {
    angular.module("App")
        .controller("reportController", [
            "$scope",
            "reportService",
            "alertService",
            "$route",
            "$window",
            "$location",
            "spinnerAPI",
            function(
                $scope,
                reportService,
                alertService,
                $route,
                $window,
                $location,
                spinnerAPI
            ) {

                var view, report;

                function initialize() {

                    /**
                         * The view model. Contains items only needed for the view.
                         *
                         * @property {String}  step                     The name of the form submission step the user is on
                         * @property {String}  vendorId                 The vendor_id from the API
                         * @property {Object}  isDisabled               Contains various standardized disabled flags
                         *     @property {Boolean} isDisabled.rule      Is the rule itself disabled?
                         *     @property {Boolean} isDisabled.config    Is the config housing this rule disabled?
                         *     @property {Boolean} isDisabled.vendor    Is the vendor providing this rule disabled?
                         *     @property {Boolean} isDisabled.overall   Is the rule disabled at any of the previous levels?
                         * @property {Number}  includedHitCount         The number of included hits in the report
                         * @property {Object}  expandedHit              The hit object that is currently expanded
                         * @property {Object}  form                     The angular form controller for the main form
                         * @property {Object}  loading                  An object with basic loading flags.
                         *     @property {Boolean} loading.init         Are the hits and rule loading?
                         *     @property {Boolean} loading.report       Is the generated report loading?
                         * @property {Boolean} submitting               Is the report submitting?
                         * @property {Boolean} rawReportActive          Is the rawReport tab active?
                         * @property {Array}   lastIncludedHitIds         This is an array of hit IDs that were included in the last report generated for the raw report tab
                         */
                    view = $scope.view = {
                        step: "input",
                        loading: {
                            init: false,
                            report: false
                        },
                        submitting: false,
                        ruleExpanded: false
                    };

                    /**
                         * This object stores all of the items relevant to generating and submitting a report.
                         *
                         * @property {Array}  hits     An array of hit objects that are associated with the rule
                         * @property {Object} rule     The rule object for the rule being reported
                         * @property {Object} inputs   The values that the user inputs on the form
                         */
                    report = $scope.report = {
                        hits: null,
                        rule: null,
                        inputs: {}
                    };

                    // pathParams should include hitId or ruleId properties
                    _getReport($route.current.pathParams).then(_updateViewModel);
                }

                /**
                     * Attempts to get the last promise from the report service that was created using fetchByHit
                     * or fetchByRule. If it's not available, use the lookup object to get a new one. This promise
                     * resolves with a rule object a list of associated hits and is used to populate the report
                     * $scope object.
                     *
                     * @param  {Object} lookup   This object should have either a hitId or ruleId/vendorId property
                     * @return {Promise}         This is either cached or newly fetched promise
                     */
                function _getReport(lookup) {
                    view.loading.init = true;

                    // Check to see if there's a cached promise. If not, get a new one depending on the lookup data.
                    var reportPromise = reportService.getCurrent();
                    if (!reportPromise) {
                        if (lookup.hitId) {
                            reportPromise = reportService.fetchByHit(lookup.hitId);
                        } else if (lookup.ruleId && lookup.vendorId) {
                            reportPromise = reportService.fetchByRule(lookup.ruleId, lookup.vendorId);
                        } else {
                            throw new ReferenceError("Cannot populate the report without a ruleId or hitId.");
                        }
                    }

                    reportPromise.then(
                        function success(response) {
                            if (report.invalid) {
                                delete report.invalid;
                            }

                            report.rule = response.rule;
                            report.hits = response.hits.map(function(hit) {
                                hit.included = true;
                                return hit;
                            });
                            view.includedHitCount = report.hits.length;
                        },
                        function failure(error) {
                            report.invalid = true;
                            if (error && error.message) {
                                alertService.add({
                                    type: "danger",
                                    message: error.message,
                                    id: "report-retrieval-error"
                                });
                            } else {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "report-retrieval-error"
                                });
                            }
                        }
                    ).finally(function() {
                        view.loading.init = false;
                    });

                    return reportPromise;
                }

                /**
                     * Update various bits of the view model with the results from the initial fetch.
                     *
                     * @method _updateViewModel
                     */
                function _updateViewModel() {
                    view.vendorId = report.rule.vendor_id;
                    view.isDisabled = {
                        overall: report.rule.disabled || !report.rule.config_active || !report.rule.vendor_active,
                        rule: report.rule.disabled,
                        config: !report.rule.config_active,
                        vendor: !report.rule.vendor_active
                    };
                }

                /**
                     * Get the text for the page title. If we have a vedor ID string, then we'll use it.
                     *
                     * @method getTitleText
                     * @return {String}   The title
                     */
                function getTitleText() {
                    return view.vendorId ?
                        LOCALE.maketext("Report a [asis,ModSecurity] Rule to [_1]", view.vendorId) :
                        LOCALE.maketext("Report a [asis,ModSecurity] Rule");
                }

                /**
                     * Is the hit currently expanded?
                     *
                     * @method isExpanded
                     * @param  {Object}  hit   A hit object
                     *
                     * @return {Boolean}       Is it expanded?
                     */
                function isExpanded(hit) {
                    return view.expandedHit === hit;
                }

                /**
                     * Toggle the expanded or collapsed state of a hit in the table
                     * view. Only one hit will be expanded at a time.
                     *
                     * @method toggleExpandCollapse
                     * @param  {Object} hit   A hit object
                     */
                function toggleExpandCollapse(hit) {
                    view.expandedHit = view.expandedHit === hit ? null : hit;
                }

                /**
                     * Toggles the state of the hit as included or excluded from the report.
                     *
                     * @method toggleIncludeExclude
                     * @param  {Object} hit   A hit object
                     */
                function toggleIncludeExclude(hit) {
                    if (view.includedHitCount === 1) {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("You must include at least one hit record with your report."),
                            id: "report-last-hit-info"
                        });
                        return;
                    }

                    hit.included = !hit.included;
                    view.includedHitCount--;
                }

                /**
                     * Generates an array of hit IDs that the user has elected to include with the report.
                     * @return {Array}   An array of numbers corresponding to hit IDs.
                     */
                function _includedHitIds() {
                    var includedHits = [];

                    if (report.hits) {
                        report.hits.forEach(function(hit) {
                            if (hit.included) {
                                includedHits.push(hit.id);
                            }
                        });
                    }

                    return includedHits;
                }

                /**
                     * Gathers all of the required report parameters together.
                     *
                     * @method _consolidateReportInputs
                     * @return {Object}   An object suitable to pass to the reportService as reportParams
                     */
                function _consolidateReportInputs() {
                    return {
                        hits: _includedHitIds(),
                        email: report.inputs.email,
                        reason: report.inputs.reason,
                        message: report.inputs.comments
                    };
                }

                /**
                     * Duct tape for a bug with UI Bootstrap tabs that has already been fixed upstream.
                     * Basically the select callbacks are run on $destroy so it resulted in extra net
                     * requests for no reason.
                     *
                     * Issue thread here: https://github.com/angular-ui/bootstrap/issues/2155
                     * Fixed here: https://github.com/lanetix/bootstrap/commit/4d77f3995bb357741a86bcd48390c8bb2e9954e7
                     */
                var destroyed;
                $scope.$on("$destroy", function() {
                    destroyed = true;
                });

                /**
                     * Callback when changing tabs.
                     *
                     * @method changeToTab
                     * @param  {String} tabName   The name of the tab
                     */
                function changeToTab(tabName) {
                    if (!destroyed) { // See workaround documentation directly above this method

                        // Trying to remove the last hit in the associated hit list gives an alert, so remove it if we're heading to another tab
                        if (tabName !== "hitList") {
                            alertService.removeById("report-last-hit-info");
                        }

                        // If it's the raw report tab, fetch the report
                        if (tabName === "rawReport") {
                            _updateRawTab();
                        }
                    }
                }

                /**
                     * Check to see if the included hits have changed since the last preview was generated.
                     *
                     * @method _includedHitIdsChanged
                     * @return {Boolean}   True if the included hit ids have changed
                     */
                function _includedHitIdsChanged() {
                    var currentIds = _includedHitIds();

                    if (!view.lastIncludedHitIds || currentIds.length !== view.lastIncludedHitIds.length) {
                        return false;
                    } else {
                        return currentIds.some(function(val, index) {
                            return view.lastIncludedHitIds.indexOf(val) === -1;
                        });
                    }
                }

                /**
                     * Check to see if the generated report in the raw tab is stale, i.e. there
                     * is new information in the form or if the selected/included hits differ from
                     * the last time the report was generated.
                     *
                     * @method rawTabIsStale
                     * @return {Boolean}   True if the generated report is stale
                     */
                function rawTabIsStale() {
                    return view.form.$dirty || _includedHitIdsChanged();
                }

                /**
                     * Fetches the JSON for the generated report and updates report.json
                     *
                     * @method _updateRawTab
                     */
                function _updateRawTab() {
                    if (rawTabIsStale()) {

                        // Reset the two stale conditions
                        view.form.$setPristine();
                        view.lastIncludedHitIds = _includedHitIds();

                        viewReport().then(
                            function(response) {
                                report.json = JSON.stringify(response, false, 2);
                            },
                            function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "fetch-generated-report-error"
                                });
                            }
                        );
                    }
                }

                /**
                     * Fetch a generated report.
                     *
                     * @method viewReport
                     * @return {Promise}   Resolves with the report as a parsed object.
                     */
                function viewReport() {
                    view.loading.report = true;

                    return reportService.viewReport(_consolidateReportInputs()).finally(function() {
                        view.loading.report = false;
                    });
                }

                /**
                     * Submit the report and optionally disable the rule.
                     *
                     * @method submitReport
                     * @return {Promise}   Resolves when the report has been sent and the rule has
                     *                     been disabled, if the user chose to disable the rule.
                     */
                function submitReport() {
                    alertService.clear();
                    view.submitting = true;

                    var promise, disableParams;

                    // Send disable params if the rule is enabled and the user wants to disable
                    if (!view.isDisabled.rule && report.inputs.disableRule) {
                        disableParams = {
                            deployRule: report.inputs.deployRule,
                            ruleConfig: report.rule.config,
                            ruleId: report.rule.id
                        };

                        promise = reportService.sendReport(_consolidateReportInputs(), disableParams);
                    } else {
                        promise = reportService.sendReport(_consolidateReportInputs());
                    }

                    promise.then(
                        function success(response) {
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("You have successfully submitted a report for the rule ID “[_1]” to “[_2]”.", report.rule.id, view.vendorId),
                                id: "report-rule-submit-success"
                            });

                            $scope.loadView("hitList");
                        },
                        function failure(error) {
                            alertService.add({
                                type: "warning",
                                message: error,
                                id: "report-rule-submit-error"
                            });
                        }
                    ).finally(function() {
                        view.submitting = false;
                    });

                    return promise;
                }

                /**
                     * The user no longer wants to submit the report, so send them back to where
                     * they came from if we have history. If not, take them to the appropriate
                     * place based on their route params.
                     *
                     * @method cancelSubmission
                     */
                function cancelSubmission() {
                    alertService.clear();

                    if ($location.state) {
                        $window.history.back();
                    } else if ($route.current.pathParams.hitId) {
                        $scope.loadView("hitList");
                    } else {
                        $scope.loadView("rulesList");
                    }
                }

                /**
                     * Changes the submission step.
                     *
                     * @param  {String} newStep   The name of the new step
                     */
                function changeStep(newStep) {
                    view.step = newStep;

                    // If we're coming back to the review page and the raw tab is active,
                    // we need to update the report.
                    if (newStep === "review" && view.rawReportActive) {
                        _updateRawTab();
                    }
                }

                // Extend scope with the public methods
                angular.extend($scope, {
                    getTitleText: getTitleText,
                    isExpanded: isExpanded,
                    toggleExpandCollapse: toggleExpandCollapse,
                    toggleIncludeExclude: toggleIncludeExclude,
                    changeToTab: changeToTab,
                    viewReport: viewReport,
                    submitReport: submitReport,
                    cancelSubmission: cancelSubmission,
                    changeStep: changeStep,
                    rawTabIsStale: rawTabIsStale
                });

                initialize();
            }
        ])
        .filter("onlyTrueHitFields", function() {
            var EXCLUDED_KEYS = ["included", "reportable", "file_exists"];

            /**
                 * Filters out any fields that are added to modsec_get_log results that don't exist in the database.
                 * @param  {Object} hitObj   The hit object
                 *
                 * @return {Object}          A copy of the hit object with synthetic keys filtered out
                 */
            return function(hitObj) {
                var filteredObj = {};
                angular.forEach(hitObj, function(val, key) {
                    if (EXCLUDED_KEYS.indexOf(key) === -1) {
                        filteredObj[key] = val;
                    }
                });

                return filteredObj;
            };
        });
}
);
