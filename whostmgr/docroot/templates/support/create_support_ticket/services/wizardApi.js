/*
 * whostmgr/docroot/templates/support/create_support_ticket/service/wizardApi.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/services/viewNavigationApi"
    ],
    function(angular, _, LOCALE) {

        var app = angular.module("whm.createSupportTicket");

        app.factory("wizardApi", [
            "viewNavigationApi",
            "wizardState",
            function(viewNavigationApi, wizardState) {

                /**
                 * Get a suitable prefix for IDs associated with the wizard. This prefix is
                 * derived from the current view of the wizard. It basically just removes any
                 * leading or trailing forward slashes if they exist and converts any other
                 * forward slashes to dashes.
                 *
                 * @method  _getIdPrefix
                 * @private
                 * @return {String}   The ID prefix.
                 */
                function _getIdPrefix() {
                    var view = wizardState.view || "wizard";
                    return _.kebabCase(view);
                }

                return {

                    /**
                     * Configure the common wizard options. Generally this is called only once. To
                     * configure individual steps call wizardAPI.configureStep()
                     *
                     * @name  configureWizardStep
                     * @param {Object} [opts] Collection of customizations to the wizard process.
                     * @param {Function} [opts.resetFn]             Function to call when navigating to the first step
                     * @param {Function} [opts.nextFn]              Function to call when navigating to the next step
                     * @param {String}   [opts.nextButtonText]      Name to show on the next button.
                     * @param {String}   [opts.nextButtonTitle]     Title for the next button.
                     * @param {Function} [opts.previousFn]          Function to call when navigating to the previous step
                     * @param {String}   [opts.previousButtonText]  Name to show on the previous button.
                     * @param {String}   [opts.previousButtonTitle] Title for the previous button.
                     */
                    configure: function(opts) {
                        opts = opts || {};
                        wizardState.resetFn             = opts.resetFn || angular.noop;
                        wizardState.nextButtonTitle     = opts.nextButtonTitle || "";
                        wizardState.nextButtonText      = opts.nextButtonText || LOCALE.maketext("Next");
                        wizardState.nextFn              = opts.nextFn || angular.noop;
                        wizardState.previousButtonTitle = opts.nextButtonTitle || "";
                        wizardState.previousButtonText  = opts.previousButtonText || LOCALE.maketext("Previous");
                        wizardState.previousFn          = opts.previousFn || angular.noop;
                    },

                    /**
                     * Get the current step
                     *
                     * @return {Number} Current step number.
                     */
                    getStep: function() {
                        return wizardState.step;
                    },

                    /**
                     * Get the view the wizard thinks its on
                     * @return {String}
                     */
                    getView: function() {
                        return wizardState.view;
                    },

                    /**
                     * Reset the wizard to it initial state. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name reset
                     */
                    reset: function() {
                        if (wizardState.resetFn.apply(wizardState, arguments) ||
                            wizardState.resetFn === angular.noop) {
                            wizardState.step = 1;
                        }
                    },

                    /**
                     * Navigate to the next step. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name next
                     */
                    next: function() {
                        if (wizardState.nextFn.apply(wizardState, arguments) ||
                            wizardState.nextFn === angular.noop) {
                            wizardState.step++;
                        }

                        this.setButtonIds();

                        // Prevent overflow
                        if (wizardState.step > wizardState.maxSteps) {
                            wizardState.step = wizardState.maxSteps;
                        }
                    },

                    /**
                     * Navigate to the previous step. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name previous
                     */
                    previous: function() {
                        if (wizardState.previousFn.apply(wizardState, arguments) ||
                            wizardState.previousFn === angular.noop) {
                            wizardState.step--;
                        }

                        this.setButtonIds();

                        // Prevent overflow
                        if (wizardState.step <= 0) {
                            wizardState.step = 1;
                        }
                    },

                    /**
                     * Hide the wizard control footer.
                     *
                     * @name  hideFooter
                     */
                    hideFooter: function() {
                        wizardState.footer = false;
                    },

                    /**
                     * Show the wizard control footer.
                     *
                     * @name  showFooter
                     */
                    showFooter: function() {
                        wizardState.footer = true;
                    },

                    /**
                     * Disable the Next button in the wizard. This may be used to stop the user from
                     * moving forward until they complete some task on the current step.
                     *
                     * @scope
                     * @name  disableNextButton
                     */
                    disableNextButton: function() {
                        wizardState.nextButtonDisabled = true;
                    },

                    /**
                     * Enable the Next button in the wizard.
                     *
                     * @scope
                     * @name  enableNextButton
                     */
                    enableNextButton: function() {
                        wizardState.nextButtonDisabled = false;
                    },

                    /**
                     * Sets IDs on the next and previous buttons based on the prefix that is passed in
                     * or the view name.
                     *
                     * @method setButtonIds
                     * @param {String} [prefix]   Optional prefix for the button IDs.
                     */
                    setButtonIds: function(prefix) {
                        prefix = prefix || _getIdPrefix();
                        wizardState.nextButtonId     = prefix + "-next-button";
                        wizardState.previousButtonId = prefix + "-previous-button";
                    },

                    /**
                     * Configure the current wizard step. During configuration the
                     * wizards next and previous action functions are registered along
                     * with other next/previous button configuration.
                     *
                     * @name  configureStep
                     * @param {Object} [opts] Collection of customizations to the wizard process.
                     * @param {Function} [opts.nextFn]              Function to call when navigating to the next step
                     * @param {String}   [opts.nextButtonText]      Name to show on the next button.
                     * @param {String}   [opts.nextButtonTitle]     Title for the next button.
                     * @param {Function} [opts.previousFn]          Function to call when navigating to the previous step
                     * @param {String}   [opts.previousButtonText]  Name to show on the previous button.
                     * @param {String}   [opts.previousButtonTitle] Title for the previous button.
                     * @return {Boolean} if true it initialized correctly. if false it reset the wizard.
                     */
                    configureStep: function(opts) {
                        opts = opts || {};

                        wizardState.nextButtonTitle     = opts.nextButtonTitle || "";
                        wizardState.nextButtonText      = opts.nextButtonText || LOCALE.maketext("Next");
                        wizardState.nextFn              = opts.nextFn || angular.noop;
                        wizardState.previousButtonTitle = opts.previousButtonTitle || "";
                        wizardState.previousButtonText  = opts.previousButtonText || LOCALE.maketext("Previous");
                        wizardState.previousFn          = opts.previousFn || angular.noop;

                        return true;
                    },

                    /**
                     * Loads the specified view
                     *
                     * @method loadView
                     * @param {String} path        The path to the view, relative to the docroot.
                     * @param {Object} [query]     Optional query string properties passed as a hash.
                     * @param {Object} [options]   Optional hash of options.
                     *     @param {Boolean} [options.clearAlerts]    If true, the default alert group in the alertService will be cleared.
                     *     @param {Boolean} [options.replaceState]   If true, the current history state will be replaced by the new view.
                     * @return {$location}         Angular's $location service.
                     * @see cjt2/services/viewNavigationApi.js
                     */
                    loadView: function(path, query, options) {
                        var location = viewNavigationApi.loadView(path, query, options);
                        wizardState.view = path;
                        return location;
                    },

                    /**
                     * Verify if the steps path is where we expected it to
                     * be for this controller.
                     *
                     * @method verifyStep
                     * @param {String|Regexp} expectedPath Path or pattern of path we expected.
                     * @param {Function}      [fn]         Optional callback function. If not provided, the wizardApi.reset()
                     *                                     is called, otherwise it calls the callback.
                     *                                     fn should have the following signature:
                     *                                         fn(current, expected)
                     *                                     where:
                     *                                        current  - String - current path
                     *                                        expected - String - expected path
                     * @return {Boolean}                    true if the path and expectedPath match, false otherwise.
                     */
                    verifyStep: function(expectedPath, fn) {
                        var expectedPathRegexp = angular.isString(expectedPath) ? new RegExp("^" + _.escapeRegExp(expectedPath) + "$") : expectedPath;
                        if (!expectedPathRegexp instanceof RegExp) {
                            throw "expectedPath is not a valid expression. It must be a string or a RegExp";
                        }

                        var currentPath = this.getView();
                        if (!expectedPathRegexp.test(currentPath)) {
                            if (fn && angular.isFunction(fn)) {
                                fn(currentPath, expectedPath);
                            } else {
                                this.reset();
                            }
                            return false;
                        }
                        return true;
                    },

                    /**
                     * Current number of steps. Works as a getter and setter.
                     *
                     * @property steps
                     * @param  {Number} [steps] Number of steps.
                     * @return {Number}         Number of steps.
                     */
                    steps: function(steps) {
                        if (!angular.isUndefined(steps)) {
                            wizardState.maxSteps = steps;
                        }
                        return wizardState.maxSteps;
                    }
                };
            }
        ]);
    }
);
