/*
# templates/mod_security/views/commonController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/* ------------------------------------------------------------------------------
* DEVELOPER NOTES:
*  1) Put all common application functionality here, maybe
*-----------------------------------------------------------------------------*/

define(
    'app/views/commonController',[
        "angular",
        "cjt/filters/wrapFilter",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "uiBootstrap"
    ],
    function(angular) {

        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", ["ui.bootstrap", "ngSanitize"]);
        }

        var controller = app.controller(
            "commonController",
            ["$scope", "$location", "$rootScope", "alertService", "PAGE",
                function($scope, $location, $rootScope, alertService, PAGE) {

                // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    // Bind the alerts service to the local scope
                    $scope.alerts = alertService.getAlerts();

                    $scope.route = null;

                    /**
                 * Closes an alert and removes it from the alerts service
                 *
                 * @method closeAlert
                 * @param {String} index The array index of the alert to remove
                 */
                    $scope.closeAlert = function(id) {
                        alertService.remove(id);
                    };

                    /**
                 * Determines if the current view matches the supplied pattern
                 *
                 * @method isCurrentView
                 * @param {String} view The path to the view to match
                 */
                    $scope.isCurrentView = function(view) {
                        if ( $scope.route && $scope.route.$$route ) {
                            return $scope.route.$$route.originalPath === view;
                        }
                        return false;
                    };

                    // register listener to watch route changes
                    $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        $scope.route = next;
                    });
                }
            ]);


        return controller;
    }
);

/*
# mod_security/services/configService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/configService',[

        // Libraries
        "angular",

        // CJT
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Apply the defaults to the config if needed.
         * @param  {Array} configs
         */
        function applyDefaults(config) {
            if (config.default && config.missing) {
                if (config.type === "number") {
                    config.state = parseInt(config.default, 10);
                } else {
                    config.state = config.default;
                }
            }
        }

        /**
         * Converts the response to our application data structure
         * @method convertResponseToList
         * @private
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function convertResponseToList(response) {
            var items = [];
            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var config = data[i];

                    // Clean up the boolean data
                    if (typeof (config.engine) !== "undefined") {
                        config.engine = PARSE.parsePerlBoolean(config.engine);
                    }

                    // Apply the default if the config is missing
                    applyDefaults(config);

                    // Mark the record as unchanged
                    config.changed = false;

                    items.push(
                        config
                    );
                }

                return items;
            } else {
                return [];
            }
        }

        /**
         * Setup the configuration models API service
         */
        app.factory("configService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var ConfigService = function() {};
            ConfigService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(ConfigService.prototype, {

                /**
                 * Get a list of mod_security rule hits that match the selection criteria passed in meta parameter
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_settings");
                    var deferred = this.deferred(apiCall, { transformAPISuccess: convertResponseToList });
                    return deferred.promise;
                },

                /**
                 * Save the changed configurations.
                 * @param  {Array} configs
                 * @return {Promise} Promise that will fulfill the request.
                 */
                save: function(configs) {
                    if (!configs) {
                        return;
                    }

                    var toSave = [];
                    for (var i = 0, l = configs.length; i < l; i++) {
                        if (configs[i].changed) {
                            toSave.push(configs[i]);
                        }
                    }

                    if (toSave.length > 0 ) {

                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "modsec_batch_settings");
                        for (var j = 0, jl = toSave.length; j < jl; j++) {
                            var item = toSave[j];
                            if (
                                (!item.engine && item.default && (                                                        // Not an engine and has a default
                                    ((item.type === "text" || item.type === "radio") && (item.state === item.default)) || // Text or radio field with a default set to default, but not missing from file
                                    (item.type === "number" && (parseInt(item.state, 10) === item.default))               // Number field with a default set to default, but not missing from file
                                )) ||
                                (item.state === "") // Text or number that has been cleared, but isn't missing from file
                            ) {
                                if (!item.missing) {
                                    apiCall.addArgument("setting_id", toSave[j].setting_id, true);
                                    apiCall.addArgument("remove", 1, true);

                                    // Otherwise, nothing to do here.
                                }
                            } else {
                                apiCall.addArgument("setting_id", toSave[j].setting_id, true);
                                apiCall.addArgument("state", item.state, true);
                            }
                            apiCall.incrementAuto();
                        }
                        apiCall.addArgument("commit", 1);

                        var deferred = this.deferred(apiCall, {
                            apiSuccess: function(response, deferred) {
                                for (var i = 0, l = configs.length; i < l; i++) {
                                    if (configs[i].changed) {
                                        configs[i].changed = false;
                                    }
                                }

                                deferred.resolve(response.data);
                            },
                            apiFailure: function(response) {

                                // TODO: Get the list from the data
                                deferred.reject(response.error);
                            }
                        });

                        // pass the promise back to the controller
                        return deferred.promise;
                    }
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return convertResponseToList(response);
                },

                /**
                 * Apply the defaults to the config if needed.
                 * @param  {Array} configs
                 */
                applyDefaults: applyDefaults
            });

            return new ConfigService();
        }]);
    }
);

/*
# templates/mod_security/views/configController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/configController',[
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

/*
# templates/mod_security/config.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/config',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {

        // First create the application
        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load first
            "ngRoute",
            "ui.bootstrap",
            "cjt2.whm"
        ]);

        // Then load the application dependencies
        var app = require(
            [
                "cjt/bootstrap",
                "cjt/util/locale",

                // Application Modules
                "cjt/views/applicationController",
                "app/views/commonController",
                "app/views/configController",
                "cjt/services/autoTopService",
                "cjt/services/whm/breadcrumbService",
                "cjt/services/whm/titleService"
            ], function(BOOTSTRAP, LOCALE) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.firstLoad = {
                    configs: true,
                    vendors: true
                };

                // routing
                app.config(["$routeProvider",
                    function($routeProvider) {

                        // Configuration
                        $routeProvider.when("/config", {
                            controller: "configController",
                            templateUrl: CJT.buildFullPath("mod_security/views/configView.ptt"),
                            breadcrumb: LOCALE.maketext("Configure Global Directives"),
                            title: LOCALE.maketext("Configure Global Directives"),
                            reloadOnSearch: false,
                            group: "config",
                            name: "config"
                        });

                        $routeProvider.otherwise({
                            redirectTo: function(routeParams, path, search) {
                                return "/config?" + window.location.search;
                            }
                        });
                    }
                ]);

                app.run(["autoTopService", "breadcrumbService", "titleService", function(autoTopService, breadcrumbService, titleService) {

                    // Setup the automatic scroll to top for view changes
                    autoTopService.initialize();

                    // Setup the breadcrumbs service
                    breadcrumbService.initialize();

                    // Setup the title update service
                    titleService.initialize();
                }]);

                BOOTSTRAP(document);

            });

        return app;
    }
);

