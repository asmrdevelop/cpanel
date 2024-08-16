/*
 * templates/multiphp_manager/views/poolOptions.js
 *                                                 Copyright 2022 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* eslint no-use-before-define: 0*/

define(
    [
        "angular",
        "lodash",
        "cjt/util/parse",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/configService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/toggleLabelInfoDirective",
        "cjt/directives/loadingPanel",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/path-validators",
    ],
    function(angular, _, PARSE, LOCALE) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "poolOptionsController",
            ["$q", "$scope", "$anchorScroll", "$rootScope", "alertService", "configService",
                function($q, $scope, $anchorScroll, $rootScope, alertService, configService) {

                    $scope.displayValue = {
                        selectedDomain: "",
                        docRootDisplayValue: "",
                        logDirDisplayValue: "",
                        reportedErrs: "",
                        disabledFuncs: "",
                        displayMode: null,
                        disabledFuncsPanelOpen: false,
                        errsReportedPanelOpen: false,
                        saveReminderDisplayed: false,
                        saveReminderMessage: LOCALE.maketext("Click [output,em,Save Configuration] to save your changes."),
                    };

                    $scope.poolOptions = {};
                    $scope.poolOptionsCache = {};

                    $scope.additionalResources = [
                        {
                            text: "cPanel Documentation",
                            link: "https://docs.cpanel.net/",
                        },
                        {
                            text: LOCALE.maketext("Official [asis,PHP] Configuration Documentation"),
                            link: "https://secure.php.net/manual/en/install.fpm.configuration.php",
                        },
                        {
                            text: "Bottleneck with Child Processes",
                            link: "https://go.cpanel.net/ApachevsPHP-FPMBottleneckwithChildProcesses",
                        },
                    ];

                    /**
                 * Return default button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getDefaultButtonClasses
                 */
                    $scope.getDefaultButtonClasses = function() {
                        return "btn btn-default";
                    };

                    /**
                 * Return small default button classes to work with cp-action directive
                 * @method getSmallDefaultButtonClasses
                 */
                    $scope.getSmallDefaultButtonClasses = function() {
                        return "btn btn-sm btn-default";
                    };

                    /**
                 * Return default button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getButtonClasses
                 * @return {String}         Default button classes
                 */
                    $scope.getButtonClasses = function() {
                        return "btn btn-default";
                    };

                    /**
                 * Return primary button classes to work with cp-action directive
                 *
                 * @scope
                 * @method getPrimaryButtonsClasses
                 * @return {String}           Promary button classes
                 */
                    $scope.getPrimaryButtonsClasses = function() {
                        return "btn btn-sm btn-primary";
                    };

                    /**
                 * Add functions to the disable_functions value list
                 *
                 * @scope
                 * @method addFunctionsToDisable
                 * @param  {Array.<String>}      funcs   array of functions to validate for disabling
                 * @param  {Object}              formVal object representing php-fpm form
                 * @return {Promise.<Array.<String>> | } if the promise exists it returns an array of strings of validated funcs, if the promise does not exist, the function returns nothing
                 */
                    $scope.addFunctionsToDisable = function(funcs, formVal) {
                        var funcsPromises = formatAndValidateFunctions(funcs, formVal);
                        if (!funcsPromises) {
                            return;
                        }
                        $scope.actions.validatingFuncs = true;
                        return funcsPromises.then(function(validatedFuncs) {
                            alertService.add({
                                type: "success",
                                autoClose: 5000,
                                message: LOCALE.maketext("You successfully added the “[_1]” function to the list. Click [output,em,Save Configuration] to save your changes.", _.escape(validatedFuncs)),
                            });
                            $scope.actions.validatingFuncs = false;
                        });
                    };

                    /**
                 * Remove functions from disable_functions value list
                 *
                 * @scope
                 * @method removeDisabledFunction
                 * @param  {String}               func    function to remove from disable_functions value list
                 * @param  {Object}               formVal object representing php-fpm form
                 */
                    $scope.removeDisabledFunction = function(func, formVal) {
                        var commands = $scope.poolOptions.disable_functions.value;
                        for (var i = 0, len = $scope.poolOptions.disable_functions.value.length; i < len; i++) {
                            if (func === commands[i]) {
                                $scope.poolOptions.disable_functions.value.splice(i, 1);
                                formVal.$setDirty();
                                return;
                            }
                        }
                    };

                    /**
                 * Add errors to error_reporting value list
                 *
                 * @scope
                 * @method addErrsToReport
                 * @param  {Array.<String>}           errs    array of errors to validate before adding to error_reporting value list
                 * @param  {Object}                   formVal object representing php-fpm form
                 * @return {Promise.<Array.<String>>}         if the promise exists it returns and array of strings of validated errors, if it does not exist the function return nothing
                 */
                    $scope.addErrsToReport = function(errs, formVal) {
                        var errsPromises = formatAndValidateErrs(errs, formVal);
                        if (!errsPromises) {
                            return;
                        }
                        $scope.actions.validatingErrs = true;
                        return errsPromises.then(function(validatedErrs) {
                            alertService.add({
                                type: "success",
                                autoClose: 5000,
                                message: LOCALE.maketext("You successfully added the “[_1]” error to the list. Click [output,em,Save Configuration] to save your changes.", _.escape(validatedErrs)),
                            });
                            $scope.actions.validatingErrs = false;
                        });
                    };

                    /**
                 * Remove errors from error_reporting value list
                 *
                 * @scope
                 * @method removeReportedErrs
                 * @param  {String}           err     error to remove from error_reporting value list
                 * @param  {Object}           formVal object representing php-fpm form
                 */
                    $scope.removeReportedErrs = function(err, formVal) {
                        var errs = $scope.poolOptions.error_reporting.value;
                        for (var i = 0, len = $scope.poolOptions.error_reporting.value.length; i < len; i++) {
                            if (err === errs[i]) {
                                $scope.poolOptions.error_reporting.value.splice(i, 1);
                                formVal.$setDirty();
                                return;
                            }
                        }
                    };

                    /**
                 * Emit event to return to PHP Version domain list view
                 *
                 * @scope
                 * @method returnToDomainsList
                 */
                    $scope.returnToDomainsList = function() {
                        $rootScope.$emit("returnToDomainList");
                    };

                    /**
                 * Toggle betwee php_value and php_admin_value for given options
                 *
                 * @scope
                 * @method toggleOverrideVal
                 * @param  {String}          overrideVal which pool option is being toggled
                 * @param  {Object}          formVal     object representing php-fpm form
                 * @throws {String}                      error informing developer of invalid value
                 */
                    $scope.toggleOverrideVal = function(overrideVal, formVal) {
                        formVal.$setDirty();

                        if (!$scope.displayValue.saveReminderDisplayed) {
                            alertService.add({
                                type: "info",
                                closeable: true,
                                autoClose: 5000,
                                message: $scope.displayValue.saveReminderMessage,
                            });
                            $scope.displayValue.saveReminderDisplayed = true;
                        }

                        switch (overrideVal) {
                            case "allow_url_fopen":
                                $scope.poolOptions.allow_url_fopen.admin = !$scope.poolOptions.allow_url_fopen.admin;
                                break;
                            case "log_errors":
                                $scope.poolOptions.log_errors.admin = !$scope.poolOptions.log_errors.admin;
                                break;
                            case "short_open_tag":
                                $scope.poolOptions.short_open_tag.admin = !$scope.poolOptions.short_open_tag.admin;
                                break;
                            case "doc_root":
                                $scope.poolOptions.doc_root.admin = !$scope.poolOptions.doc_root.admin;
                                break;
                            case "error_log":
                                $scope.poolOptions.error_log.admin = !$scope.poolOptions.error_log.admin;
                                break;
                            case "disable_functions":
                                $scope.poolOptions.disable_functions.admin = !$scope.poolOptions.disable_functions.admin;
                                break;
                            case "error_reporting":
                                $scope.poolOptions.error_reporting.admin = !$scope.poolOptions.error_reporting.admin;
                                break;
                            default:
                                throw new Error("DEVELOPER ERROR: invalid override value given");
                        }
                    };

                    /**
                 * Save new pool options
                 *
                 * @scope
                 * @method savePoolOptions
                 * @param  {Object}        formVal object representing php-fpm form
                 */
                    $scope.savePoolOptions = function(formVal) {
                        return submitPoolOptions($scope.poolOptions, false, $scope.displayValue.selectedDomain, formVal);
                    };

                    /**
                 * Validate new pool options
                 *
                 * @scope
                 * @method validatePoolOptions
                 */
                    $scope.validatePoolOptions = function() {
                        return submitPoolOptions($scope.poolOptions, true, $scope.displayValue.selectedDomain);
                    };

                    /**
                 * Set the form to pristine
                 *
                 * @scope
                 * @method deactivateSaveActions
                 * @param  {Object}              formVal object representing php-fpm form
                 */
                    $scope.deactivateSaveActions = function(formVal) {
                        formVal.$setPristine();
                    };

                    /**
                 * Reset form to initial state
                 *
                 * @scope
                 * @method resetPoolOptionsForm
                 * @param  {Object}             formVal object representing php-fpm form
                 */
                    $scope.resetPoolOptionsForm = function(formVal) {
                        $scope.poolOptions = $scope.poolOptionsCache;
                        $scope.poolOptionsCache = angular.copy($scope.poolOptions);
                        formVal.$setPristine();
                    };

                    /**
                 * Check for duplicate entries in entered list, and existing list. Format each function for validation submission
                 *
                 * @method formatAndValidateFunctions
                 * @param  {Array.<String>}           funcs   functions to format and validate
                 * @param  {Object}                   formVal object representing php-fpm form
                 * @return {Array.<Promise>}                  if functions is a duplicate, return nothing, if it isn't return array of promises from validated functions
                 */
                    function formatAndValidateFunctions(funcs, formVal) {
                        funcs = funcs.split(",");
                        funcs = formatListVals(funcs);
                        var optionForValidation;
                        var validationPromises = [];
                        var validationPromise;

                        for (var i = 0, len = funcs.length; i < len; i++) {

                            // checks for duplicates within the array entered and returns out of if()
                            // unless it is the last index of that function
                            if (funcs.indexOf(funcs[i]) !== -1 && funcs.indexOf(funcs[i], i + 1) !== -1) {
                                return;
                            }

                            // checks for duplicates in already existing function list
                            if ($scope.poolOptions.disable_functions.value.indexOf(funcs[i]) !== -1) {
                                var duplicateMessage = LOCALE.maketext("The “[_1]” function already appears on the disabled functions list.", _.escape(funcs[i]));
                                alertService.add({
                                    type: "warning",
                                    autoClose: 5000,
                                    closeable: true,
                                    message: duplicateMessage,
                                });
                                if (len === 1) {
                                    return;
                                } else {
                                    continue;
                                }
                            }

                            optionForValidation = {
                                disable_functions: {
                                    value: [],
                                    admin: $scope.poolOptions.disable_functions.admin,
                                },
                            };
                            optionForValidation.disable_functions.value.push(funcs[i]);
                            validationPromise = validateInlineOption(optionForValidation, true, $scope.displayValue.selectedDomain, formVal);
                            validationPromises.push(validationPromise);
                        }
                        return $q.all(validationPromises);
                    }

                    /**
                 * Check for duplicate entries in entered error list, and existing error list. Format each error for validation submission
                 *
                 * @method formatAndValidateErrs
                 * @param  {Array.<String>}        errs    errors to format and validate
                 * @param  {Object}                formVal object representing php-fpm form
                 * @return {Array.<Promise>}                      if error is a duplicate, return nothing, if it isn't return array of promises from validated errors
                 */
                    function formatAndValidateErrs(errs, formVal) {
                        errs = errs.split(",");
                        errs = formatListVals(errs);
                        var optionForValidation;
                        var validationPromises = [];
                        var validationPromise;

                        for (var i = 0, len = errs.length; i < len; i++) {

                            // checks for duplicates within the array entered and returns out of if()
                            // unless it is the last index of that function
                            if (errs.indexOf(errs[i]) !== -1 && errs.indexOf(errs[i], i + 1) !== -1) {
                                return;
                            }

                            // checks for duplicates in already existing function list
                            if ($scope.poolOptions.error_reporting.value.indexOf(errs[i]) !== -1) {
                                var duplicateMessage = LOCALE.maketext("The “[_1]” error already appears on the errors list.", _.escape(errs[i]));
                                alertService.add({
                                    type: "warning",
                                    autoClose: 5000,
                                    closeable: true,
                                    message: duplicateMessage,
                                });
                                if (len === 1) {
                                    return;
                                } else {
                                    continue;
                                }
                            }

                            optionForValidation = {
                                error_reporting: {
                                    value: [],
                                    admin: $scope.poolOptions.error_reporting.admin,
                                },
                            };
                            optionForValidation.error_reporting.value.push(errs[i]);
                            validationPromise = validateInlineOption(optionForValidation, true, $scope.displayValue.selectedDomain, formVal);
                            validationPromises.push(validationPromise);
                        }
                        return $q.all(validationPromises);
                    }

                    /**
                 * Remove leading and trailing spaces from each value
                 *
                 * @method formatListVals
                 * @param  {Array.<String>}       vals array of function or error values to format
                 * @return {Array.<String>}            array of parsed error or function values
                 */
                    function formatListVals(vals) {
                        var parsedVals = [];

                        function removeSpaceChars(val) {
                            var endIndex = val.length - 1;
                            if (val.indexOf(" ") !== 0 && val.indexOf(" ") !== endIndex) {
                                return val;

                            }
                            if (val.indexOf(" ") === 0) {
                                val = val.slice(1);
                            }
                            if (val.indexOf(" ") === endIndex) {
                                val = val.slice(0, endIndex);
                            }

                            return removeSpaceChars(val);
                        }

                        vals.forEach(function(val) {
                            val = removeSpaceChars(val);
                            parsedVals.push(val);
                        });
                        return parsedVals;
                    }

                    /**
                 * Validate options entered into disable_functions or error_reporting
                 *
                 * @method validateInlineOption
                 * @param  {Object}             poolOption name and value of option to validate
                 * @param  {Boolean}            validate   boolean always set to true so that option is validated, not saved
                 * @param  {String}             [domain]   if it exists then it is validating options for that domain, if it does not the options are validated for system config
                 * @param  {[type]}             formVal    object representing php-fpm form
                 * @return {String | Promise}              on success return value of option validated, on failure return error
                 */
                    function validateInlineOption(poolOption, validate, domain, formVal) {
                        return configService.submitPoolOptions(poolOption, validate, domain)
                            .then(function(data) {

                                if (poolOption.disable_functions) {
                                    $scope.poolOptions.disable_functions.value.push(poolOption.disable_functions.value[0]);
                                    $scope.displayValue.disabledFuncsPanelOpen = true;
                                    $scope.displayValue.disabledFuncs = "";
                                    formVal.$setDirty();
                                    return poolOption.disable_functions.value[0];
                                } else if (poolOption.error_reporting) {
                                    $scope.displayValue.reportedErrs = "";
                                    $scope.poolOptions.error_reporting.value.push(poolOption.error_reporting.value[0]);
                                    $scope.displayValue.errsReportedPanelOpen = true;
                                    formVal.$setDirty();
                                    return poolOption.error_reporting.value[0];
                                }
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            });
                    }

                    /**
                 * Save or validate PHP-FPM form
                 *
                 * @method submitPoolOptions
                 * @param  {Object}          poolOptions names and value of pool options to submit
                 * @param  {Boolean}         validate    if true options are validated, if false options are saved
                 * @param  {String}          [domain]    if it exists options are saved/validated for individual domain, if it does not options are saved/validated for the system config
                 * @param  {Object}          formVal     object representing php-fpm form
                 * @return {Promise}
                 */
                    function submitPoolOptions(poolOptions, validate, domain, formVal) {
                        return configService.submitPoolOptions(poolOptions, validate, domain)
                            .then(function(data) {
                                var successMessage;
                                if (validate) {
                                    successMessage = LOCALE.maketext("The system successfully validated the [asis,PHP-FPM] configuration.");
                                } else {
                                    formVal.$setPristine();
                                    $scope.poolOptionsCache = angular.copy(poolOptions);
                                    successMessage = LOCALE.maketext("The system successfully saved the [asis,PHP-FPM] configuration.");
                                }
                                alertService.add({
                                    type: "success",
                                    message: successMessage,
                                    autoClose: 5000,
                                });
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            });
                    }

                    /**
                 * Get document root from global value
                 *
                 * @method getDocRootValue
                 * @return {String}        document root
                 */
                    function getDocRootValue() {
                        return PAGE.selectedDomainDocRoot;
                    }

                    /**
                 * Get domain home directory from global value
                 *
                 * @method getHomeDirectory
                 * @return {String}         domain home directory
                 */
                    function getHomeDirectory() {
                        return PAGE.selectedDomainHomeDir;
                    }

                    /**
                 * Get selected domain name from global values
                 *
                 * @method getSelectedDomainName
                 * @return {String}              selected domain value
                 */
                    function getSelectedDomainName() {
                        return PAGE.selectedDomainName;
                    }

                    /**
                 * Get display mode from global values
                 *
                 * @method getDisplayMode
                 * @return {String}       display mode
                 */
                    function getDisplayMode() {
                        return PAGE.poolOptionsDisplayMode;
                    }

                    /**
                 * Parse location of error log for use by front end
                 *
                 * @method parseErrorLog
                 * @param  {String}      data raw error log location
                 * @return {String}           parsed error log location
                 */
                    function parseErrorLog(data) {

                        function replacer() {
                            return "_";
                        }

                        function removeLeadingChars(log) {
                            if (log.indexOf(".") === 0) {
                                return log;

                            }
                            log = log.slice(1);
                            return removeLeadingChars(log);
                        }

                        var scrubbedDomainSplitter = "[% scrubbed_domain %]";
                        var scrubbedDomain = $scope.displayValue.selectedDomain.replace(/\./, replacer);
                        var parsedErrorLog;
                        if (data.error_log.value.indexOf(scrubbedDomainSplitter) !== -1) {
                            parsedErrorLog = removeLeadingChars(data.error_log.value.split("scrubbed_domain")[1]);
                            parsedErrorLog = scrubbedDomain + parsedErrorLog;
                            data.error_log.value = parsedErrorLog;
                        }
                        return data;
                    }

                    /**
                 * Get existing pool options
                 *
                 * @method getPoolOptions
                 * @param  {String}       [domain] if it exists fetch pool options for individual domain, if it doesn't fetch system pool options
                 */
                    function getPoolOptions(domain) {
                        return configService.getPHPFPMSettings(domain)
                            .then(function(data) {
                                if (domain) {
                                    data = parseErrorLog(data);
                                }
                                $scope.poolOptions = data;
                                $scope.poolOptionsCache = angular.copy($scope.poolOptions);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                });
                            })
                            .finally(function() {
                                scrollToFormTop();
                                $scope.actions.initialLoading = false;
                            });

                    }

                    /**
                 * Scroll to top of form
                 *
                 * @method scrollToFormTop
                 */
                    function scrollToFormTop() {
                        $anchorScroll.yOffset = -100;
                        $anchorScroll("content");
                    }

                    /**
                 * Initialize app
                 *
                 * @method init
                 */
                    function init() {

                        $scope.actions = {
                            initialLoading: true,
                            validatingFuncs: false,
                            validatingErrs: false,
                        };

                        $scope.displayValue.displayMode = getDisplayMode() || "default";
                        if ($scope.displayValue.displayMode === "domain") {
                            $scope.displayValue.docRootDisplayValue = getDocRootValue() + "/";
                            $scope.displayValue.logDirDisplayValue = getHomeDirectory() + "/logs/";
                            $scope.displayValue.selectedDomain = getSelectedDomainName();
                            getPoolOptions($scope.displayValue.selectedDomain);
                        } else {
                            getPoolOptions();
                        }

                    }
                    init();
                }]
        );
        return controller;
    }
);
