/*
# mod_security/views/enableDisableConfigController.js  Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/spinnerDirective",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/filters/breakFilter",
        "cjt/filters/replaceFilter",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationItemDirective",
        "cjt/services/alertService",
        "app/services/vendorService"
    ],
    function(angular, _, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("enableDisableConfigController", [
            "$scope",
            "$q",
            "$location",
            "$timeout",
            "vendorService",
            "alertService",
            "spinnerAPI",
            function(
                $scope,
                $q,
                $location,
                $timeout,
                vendorService,
                alertService,
                spinnerAPI) {

                /**
                 * Initialize the view
                 *
                 * @private
                 * @method _initializeView
                 */
                var _initializeView = function() {
                    $scope.filter = "";
                    $scope.filterExpression = null;
                    $scope.hasIssues = false;
                    $scope.meta = {
                        sortBy: "config",
                        sortDirection: "asc"
                    };

                    _clearIssues();

                    $scope.configs = [];
                };

                /**
                 * Load the view data
                 *
                 * @private
                 * @method _loadVendor
                 */
                var _loadVendor = function() {

                    // This control is designed to be used both independently and
                    // embedded in another controller.
                    if (!$scope.vendor) {
                        _loadVendorFromServer();
                    } else if (!$scope.vendor.configs) {
                        _loadVendorFromParent();
                    }
                };

                /**
                 * Load the force flag if it exists. This flags is used to indicate the user just enabled
                 * a vendor that did not have any enabled configuration sets.
                 *
                 * @private
                 * @method _loadForceFlag
                 */
                var _loadForceFlag = function() {
                    var value = $location.search().force;
                    if (value) {
                        $scope.force = PARSE.parseBoolean(value);
                    } else {
                        $scope.force = false;
                    }
                };

                /**
                 * Load the vendor from the server
                 *
                 * @private
                 * @method _loadVendorFromServer
                 */
                var _loadVendorFromServer = function() {
                    _loadForceFlag();

                    // Not passed from a parent controller, so do it ourselves
                    var id = $location.search().id;
                    if (id) {
                        $scope.fetch(id);
                    } else {

                        // failure
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system failed to pass the ID query string parameter."),
                            id: "errorInvalidParameterId"
                        });
                    }
                };

                /**
                 * Load the vendor from the parent passed data
                 *
                 * @private
                 * @method _loadVendorFromParent
                 */
                var _loadVendorFromParent = function() {
                    $scope.serverRequest = true;
                    _loadForceFlag();

                    if ($scope.$parent.vendor &&
                        $scope.$parent.vendor.configs) {
                        $scope.configs = $scope.$parent.vendor.configs;
                        $scope.serverRequest = false;
                        _updateTotals();
                    }
                };


                /**
                 * Updates the totalEnabled/totalDisabled counts.
                 *
                 * @method _updateTotals
                 */
                var _updateTotals = function() {
                    var totalEnabled = 0;
                    $scope.configs.forEach(function(config) {
                        if (config.enabled) {
                            totalEnabled++;
                        }
                    });

                    $scope.totalEnabled = totalEnabled;
                    $scope.totalDisabled = $scope.configs.length - totalEnabled;
                };

                // Setup a watch to recreate the filter expression if the user changes it.
                $scope.$watch("filter", function(newValue, oldValue) {
                    if (newValue) {
                        newValue = newValue.replace(/([.*+?^${}()|\[\]\/\\])/g, "\\$1"); // Escape any regex special chars (from MDN)
                        $scope.filterExpression = new RegExp(newValue, "i");
                    } else {
                        $scope.filterExpression = null;
                    }
                });

                /**
                 * Sync. filter the configs by the optional filer expression built from the filter field.
                 *
                 * @method filterConfigs
                 * @param  {String} value
                 * @return {Boolean}
                 */
                $scope.filterConfigs = function(value) {
                    return $scope.filterExpression ?
                        $scope.filterExpression.test(value.config) ||
                                (value.exception && $scope.filterExpression.test(value.exception))  :
                        true;
                };

                /**
                 * Clears the filter when the Esc key
                 * is pressed.
                 *
                 * @scope
                 * @method triggerClearFilter
                 * @param {Event} event - The event object
                 */
                $scope.triggerClearFilter = function(event) {
                    if (event.keyCode === 27) {
                        $scope.clearFilter();
                    }
                };

                /**
                 * Clear the filter.
                 *
                 * @method clearFilter
                 */
                $scope.clearFilter = function() {
                    $scope.filter = "";
                };

                /**
                 * Clear the filter only if there is one defined.
                 *
                 * @method toggleFilter
                 */
                $scope.toggleFilter = function() {
                    if ($scope.filter) {
                        $scope.clearFilter();
                    }
                };

                /**
                 * Fetch a vendor by its vendor id.
                 *
                 * @method fetch
                 * @param  {String} id Vendor id.
                 * @return {Promise}   Promise that when fulfilled will have loaded the vendor
                 */
                if (!$scope.vendor) {

                    // Only installed if not passed from the parent controller.
                    $scope.fetch = function(id) {
                        $scope.serverRequest = true;
                        spinnerAPI.start("loadingSpinner2");
                        return vendorService
                            .fetchVendorById(id)
                            .then(function(vendor) {
                                $scope.vendor = vendor;
                                $scope.configs = vendor.configs;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetchRulesList"
                                });

                            }).finally(function() {
                                $scope.serverRequest = false;
                                _updateTotals();
                                spinnerAPI.stop("loadingSpinner2");
                            });
                    };
                }

                /**
                 * Enable or disable a specific config by its path stored in the config.config property.
                 *
                 * @method setConfig
                 * @private
                 * @param  {Object} config      Configuration object
                 * @return {Promise}            Promise that when fulfilled will disable/enable the requested config.
                 */
                $scope.setConfig = function(config) {
                    var operation = config.enabled ? "enable" : "disable";

                    // Get a boolean to set config.enabled later
                    var enabling = operation === "enable";

                    // Full strings are provided here to aid localization
                    var message = enabling ?
                        LOCALE.maketext("You have successfully enabled the configuration file: [_1]", config.config) :
                        LOCALE.maketext("You have successfully disabled the configuration file: [_1]", config.config);

                    spinnerAPI.start("loadingSpinner2");
                    config.serverRequest = true;
                    return vendorService
                        [operation + "Config"](config.config) // e.g. enableConfig or disableConfig
                        .then(function() {
                            _clearIssues();
                            config.enabled = enabling;
                            if (config.exception) {
                                delete config.exception;
                            }

                            // Report success
                            alertService.add({
                                type: "success",
                                message: message,
                                id: operation + "OneSuccess"
                            });
                        }, function(error) {
                            config.enabled = !enabling;
                            config.exception = error;
                        }).finally(function() {
                            _updateIssues();
                            _updateTotals();
                            delete config.serverRequest;
                            spinnerAPI.stop("loadingSpinner2");
                        });
                };

                /**
                 * Update the configs from the outcomes. When this is done processing, the configs collection
                 * state is updated to reflect the current state on the server. Also, if any config outcome fails,
                 * the property .exception property on the specific config is filled in with the issue related to that
                 * failure so the UI can report it directly.
                 *
                 * @private
                 * @method _updateConfigs
                 * @param  {Array} configs   Collection of configs for this vendor
                 * @param  {Array} outcomes  Collection of outcome for an enable/disable all action.
                 */
                var _updateConfigs = function(configs, outcomes) {
                    angular.forEach(outcomes, function(outcome) {
                        var match = _.find(configs, function(config) {
                            return config.config === outcome.config;
                        });
                        match.enabled = outcome.enabled;
                        if (!outcome.ok) {
                            match.exception = outcome.exception;
                        } else if (match.exception) {
                            delete match.exception;
                        }
                    });
                };

                /**
                 * Update the issues flag
                 *
                 * @private
                 * @method _updateIssues
                 */
                var _updateIssues = function() {
                    var match = _.find($scope.configs, function(config) {
                        return !!config.exception;
                    });
                    $scope.hasIssues = typeof (match) !== "undefined";
                };

                /**
                 * Test if the config has a related issue meaning something went wrong.
                 *
                 * @method hasIssue
                 * @return {Boolean} true if there are any issues, false otherwise.
                 */
                $scope.hasIssue = function(config) {
                    return !!config.exception;
                };

                /**
                 * Clear the issues property in preparation for an api run.
                 *
                 * @private
                 * @method _clearIssues
                 */
                var _clearIssues = function() {
                    delete $scope.hasIssues;
                };

                /**
                 * Attempt to enabled all the configs for this vendor.
                 *
                 * @method enableAllConfigs
                 * @return {Promise} A promise that when fulfilled will enable all the configs that can be successfully
                 * enabled. The actual outcome are passed to the success handler.
                 */
                $scope.enableAllConfigs = function() {
                    return _modifyAllConfigs("enable");
                };

                /**
                 * Attempt to disabled all the configs for this vendor.
                 *
                 * @method disableAllConfigs
                 * @return {Promise} A promise that when fulfilled will disable all the configs that can be successfully
                 * enabled. The actual outcome are passed to the success handler.
                 */
                $scope.disableAllConfigs = function() {
                    return _modifyAllConfigs("disable");
                };

                /**
                 * Attempts to enable/disable all of the configs for this vendor.
                 *
                 * @method _modifyAllConfigs
                 * @private
                 * @param  {String} operation   The operation being performed on all configs, i.e. "enable" or "disable"
                 * @return {Promise}            Upon success all configs will have been modified appropriately.
                 *                              Outcomes are passed to both the success and failure handlers.
                 */
                function _modifyAllConfigs(operation) {

                    // Short circuit if no operation is necessary
                    if ((operation === "enable" && $scope.totalDisabled === 0) ||
                       (operation === "disable" && $scope.totalEnabled === 0)) {
                        return;
                    }

                    // Full strings are provided here to aid localization
                    var messages = {
                        disable: {
                            success: LOCALE.maketext("You have successfully disabled all of the configuration files."),
                            partial: LOCALE.maketext("You have successfully disabled some of the configuration files. The files that the system failed to disable are marked below."),
                            failure: LOCALE.maketext("The system could not disable the configuration files.")
                        },
                        enable: {
                            success: LOCALE.maketext("You have successfully enabled all of the configuration files."),
                            partial: LOCALE.maketext("You have successfully enabled some of the configuration files. The files that the system failed to enable are marked below."),
                            failure: LOCALE.maketext("The system could not enable the configuration files.")
                        }
                    };

                    // Begin working with the promise
                    spinnerAPI.start("loadingSpinner2");
                    $scope.serverRequest = true;
                    return vendorService
                        [operation + "AllConfigs"]($scope.vendor.vendor_id) // e.g. enableAllConfigs or disableAllConfigs
                        .then(function(outcomes) {
                            _clearIssues();
                            _updateConfigs($scope.configs, outcomes.configs);

                            // Report success
                            alertService.add({
                                type: "success",
                                message: messages[operation].success,
                                id: operation + "AllSuccess"
                            });

                        }, function(outcomes) {
                            _clearIssues();

                            if (outcomes.configs.length) {
                                _updateConfigs($scope.configs, outcomes.configs);
                                alertService.add({
                                    type: "warning",
                                    message: messages[operation].partial,
                                    id: operation + "AllWarning"
                                });
                            } else {
                                alertService.add({
                                    type: "danger",
                                    message: messages[operation].failure,
                                    id: operation + "AllError"
                                });
                            }

                        }).finally(function() {
                            _updateIssues();
                            _updateTotals();
                            $scope.serverRequest = false;
                            spinnerAPI.stop("loadingSpinner2");
                        });
                }

                /**
                 * Determines if a button should be disabled.
                 *
                 * @param  {String}  type       The button type
                 * @param  {Boolean} loading    Generic loading flag
                 * @return {Boolean}            Should the button be disabled?
                 */
                $scope.buttonDisabled = function(type, loading) {
                    if ($scope.serverRequest) {
                        return true;
                    }

                    switch (type) {
                        case "enableAll":
                            return $scope.totalDisabled === 0;
                        case "disableAll":
                            return $scope.totalEnabled === 0;
                        case "configToggle":
                            return loading;
                    }
                };

                if ($scope.$parent.vendor) {

                    // we are embedded
                    $scope.$parent.$watch("vendor.configs", function() {
                        _loadVendorFromParent();
                    });
                }

                $scope.$on("$viewContentLoaded", function() {
                    _loadVendor();
                });

                _initializeView();
            }
        ]);
    }
);
