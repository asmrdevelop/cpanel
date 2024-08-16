/*
# templates/mod_security/views/configController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/validator/datatype-validators",
        "cjt/validator/ascii-data-validators",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/directives/spinnerDirective",
        "app/services/configService",
        "cjt/directives/validationContainerDirective",
        "cjt/validator/validateDirectiveFactory",
        "cjt/directives/dynamicValidatorDirective",
        "cjt/decorators/dynamicName"
    ],
    function(angular, _, DATA_TYPE_VALIDATORS, ASCII_DATA_VALIDATORS, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "configController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "$q", "configService", "spinnerAPI", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, $q, configService, spinnerAPI, PAGE) {

                // Setup some scope variables to defaults
                    $scope.saveSuccess = false;
                    $scope.saveError = false;

                    // setup data structures for the view
                    $scope.configs = [];

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    /**
                     * SecAuditEngine directive's 'Log All' option is
                     * not recommended security wise. For this we are
                     * re-ordered the log options in UI to make sure it shows up in the end.
                     * @param  {Array} configs
                     * @return {Array}
                     */
                    var reorderSecAuditEngineOptions = function(configs) {
                        _.each(configs, function(cfg) {
                            if (cfg.directive !== "SecAuditEngine") {
                                return;
                            }
                            _.reverse(cfg.radio_options);
                            return false;
                        });
                        return configs;
                    };

                    /**
                 * Validate rules for the dynamic validation
                 * @param  {Any} value
                 * @param  {String} name
                 * @param  {Any} arg
                 * @param  {Result} result
                 * @return {Boolean}
                 */
                    $scope.validateField = function(value, name, arg, result) {
                        var regex;
                        if (!value) {
                            result.isValid = true;
                            return true;
                        }

                        var ret;
                        switch (name) {
                            case "path":
                                break;

                            case "startsWith":
                                ret = ASCII_DATA_VALIDATORS.methods.startsWith(value, arg);
                                if (!ret.isValid) {
                                    result.isValid = false;
                                    result.add(name, LOCALE.maketext("The value must start with the “[_1]” character.", "|"));
                                }
                                break;

                            case "honeypotAccessKey":

                                // http://www.projecthoneypot.org/httpbl_api.php
                                // All Access Keys are 12-characters in length, lower case, and contain only alpha characters
                                regex = /^[a-z]{12}$/;
                                if (!regex.test(value)) {
                                    result.isValid = false;
                                    result.add(name, LOCALE.maketext("The value that you provided is not a valid [asis,honeypot] access key. This value must be a sequence of 12 lower-case alphabetic characters."));
                                }
                                break;

                            case "positiveInteger":
                                ret = DATA_TYPE_VALIDATORS.methods.positiveInteger(value);
                                if (!ret.isValid) {
                                    result.isValid = false;
                                    result.add(name, ret.get("positiveInteger").message);
                                }

                                break;

                            default:
                                if (window.console) {
                                    window.console.log("Unknown validation type.");
                                }
                                break;
                        }
                        return result.isValid;
                    };

                    /**
                 * Toggles the clear button and conditionally performs a search.
                 * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                 * If the user hits <enter> in the field, its a submit action with just request the data.
                 * @param {Boolean} inSearch Toggle button clicked.
                 */
                    $scope.toggleSearch = function(inSearch) {
                        if ( !inSearch ) {
                            $scope.searchPattern = "";
                        }
                    };

                    /**
                 * Clears the search field when the user
                 * presses the Esc key
                 * @param {Event} event - The event object
                 */
                    $scope.clearSearch = function(event) {
                        if (event.keyCode === 27) {
                            $scope.searchPattern = "";
                        }
                    };

                    /**
                 * Fetch the list of hits from the server
                 * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                 */
                    $scope.fetch = function() {
                        $scope.saveSuccess = false;
                        $scope.saveError = false;
                        spinnerAPI.startGroup("loadingSpinner");
                        return configService
                            .fetchList()
                            .then(function(results) {
                                $scope.configs = reorderSecAuditEngineOptions(results);
                                spinnerAPI.stopGroup("loadingSpinner");
                            }, function(error) {
                                $scope.saveError = error;
                                spinnerAPI.stopGroup("loadingSpinner");
                            });
                    };

                    /**
                 * Disable the save button based on form state
                 * @param  {FormController} form
                 * @return {Boolean}
                 */
                    $scope.disableSave = function(form) {
                        return form.$pristine || (form.$dirty && form.$invalid);
                    };

                    /**
                 * Update the changed flag based on the event
                 * @param  {Object} setting Setting that changed.
                 */
                    $scope.changed = function(setting) {
                        setting.changed = true;
                    };

                    /**
                 * Get the field type for text fields. Either text or number.
                 * @param  {Object} setting
                 * @return {String}         text || number.
                 */
                    $scope.getFieldType = function(setting) {
                        return setting.field_type || "text";
                    };

                    /**
                 * Construct the model name from the parts
                 * @param  {String} prefix
                 * @param  {String} id
                 * @return {String}
                 */
                    $scope.makeModelName = function(prefix, id) {
                        return prefix + id;
                    };

                    /**
                 * Save the changes
                 * @param  {FormController} form
                 * @return {Promise}
                 */
                    $scope.save = function(form) {
                        $scope.saveSuccess = false;
                        $scope.saveError = false;

                        if (!form.$valid) {
                            return;
                        }

                        var promise = configService.save($scope.configs);

                        // Since the service may not return a promise,
                        // we check this first.
                        if (promise) {
                            promise.then(
                                function(data) {
                                    $scope.saveError = false;
                                    $scope.saveSuccess = true;
                                    form.$setPristine();

                                    var comparisonFactory = function(test) {
                                        return function(item) {
                                            return item.setting_id === test.setting_id;
                                        };
                                    };

                                    // Patch the defaults for items not in default state.
                                    for (var j = 0, ll = $scope.configs.length; j < ll; j++) {
                                        configService.applyDefaults($scope.configs[j]);
                                    }

                                    // Patch the state for returned items
                                    for (var i = 0, l = data.length; i < l; i++) {
                                        var config = _.find($scope.configs, comparisonFactory(data[i]));
                                        if (config) {
                                            config.state = data[i].state || data[i].default;
                                            config.missing = data[i].missing;
                                        }
                                    }

                                },
                                function(error) {
                                    $scope.saveError = error ? error : LOCALE.maketext("The system experienced an unknown error when it attempted to save the file.");
                                    $scope.saveSuccess = false;
                                }
                            ).then(function() {
                                $scope.scrollTo("top", true);
                            });

                            return promise;
                        }

                        return promise;
                    };

                    $scope.showLogAllWarning = function(radioOption, directive) {
                        return (radioOption === "On" && directive === "SecAuditEngine");
                    };

                    $scope.showLogNoteworthyLabel = function(radioOption, directive) {
                        return (radioOption === "RelevantOnly" && directive === "SecAuditEngine");
                    };

                    // check for page data in the template if this is a first load
                    if (app.firstLoad.configs && PAGE.configs) {
                        app.firstLoad.configs = false;
                        $scope.configs = configService.prepareList(PAGE.configs);
                        $scope.configs = reorderSecAuditEngineOptions($scope.configs);
                    } else {

                    // Otherwise, retrieve it via ajax
                        $scope.fetch();
                    }
                }
            ]);

        return controller;
    }
);
