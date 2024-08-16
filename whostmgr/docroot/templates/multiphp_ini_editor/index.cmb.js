/*
 * templates/multiphp_ini_editor/services/configService.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/configService',[

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
        "cjt/util/locale",

        // Angular components
        "cjt/services/APIService"
    ],
    function(angular, API, APIREQUEST, APIDRIVER, LOCALE) {
        "use strict";

        var app = angular.module("whm.multiPhpIniEditor.configService", []);

        /**
         * Converts the response to our application data structure
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function convertResponseToList(response) {
            var items = [];
            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var list = data[i];
                    items.push(
                        list
                    );
                }

                var meta = response.meta;

                var totalItems = meta.paginate.total_records || data.length;
                var totalPages = meta.paginate.total_pages || 1;

                return {
                    items: items,
                    totalItems: totalItems,
                    totalPages: totalPages
                };
            } else {
                return {
                    items: [],
                    totalItems: 0,
                    totalPages: 0
                };
            }
        }

        /**
         * Setup the account list model's API service
         */
        app.factory("configService", ["$q", function($q) {

            // return the factory interface
            return {

                /**
                 * Get a list of directives for the selected PHP version.
                 * @param {string} version - Selected PHP version
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchBasicList: function(version) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_get_directives");
                    apiCall.addArgument("version", version);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

                                // Keep the promise
                                deferred.resolve(results);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Set the new settings of basic directives for the selected PHP version.
                 * setData: JSON object with the list of PHP directives and their corresponding settings.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                applySettings: function(version, directives) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_set_directives");
                    apiCall.addArgument("version", version);

                    // Construct the directive & value arguments.
                    if (typeof (directives) !== "undefined" && directives.length > 0) {
                        directives.forEach(function(directive, index) {
                            apiCall.addArgument("directive-" + index, directive.key + ":" + directive.value);
                        });
                    }

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

                                // Keep the promise
                                deferred.resolve(results);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Get the content of the INI file for the selected PHP version.
                 * @param {string} version - Selected PHP version
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                fetchContent: function(version) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_get_content");
                    apiCall.addArgument("version", version);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {

                                // Keep the promise
                                deferred.resolve(response.data.content);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Save the new edited content of the INI file for the selected PHP version.
                 * version: The selected PHP version.
                 * content: The edited content.
                 * @return {Promise} - Promise that will fulfill the request.
                 */
                saveIniContent: function(version, content) {

                    // make a promise
                    var deferred = $q.defer();

                    var apiCall = new APIREQUEST.Class();

                    apiCall.initialize("", "php_ini_set_content");
                    apiCall.addArgument("version", version);
                    apiCall.addArgument("content", content);

                    API.promise(apiCall.getRunArguments())
                        .done(function(response) {

                            // Create items from the response
                            response = response.parsedResponse;
                            if (response.status) {
                                var results = convertResponseToList(response);

                                // Keep the promise
                                deferred.resolve(results);
                            } else {

                                // Pass the error along
                                deferred.reject(response.error);
                            }
                        });

                    // Pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Helper method that calls convertResponseToList to prepare the data structure
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
                 * Validates a PHP directive value depeding on the directive type.
                 * @param  {string} type - The type of the directive (Integer/Float/String)
                 * @param  {string} value - The value of the directive (Integer/Float/String)
                 * @return {Object} Validation data.
                 */
                validateBasicDirective: function(type, value) {
                    var text = value || "";
                    var valid = true;
                    var valMsg = "";
                    if (type === "integer") {

                        // Do the integer thing.
                        var E_FLAG = "[~!]?\\s*E_(?:(?:(?:CORE_|COMPILE_|USER_)?(?:ERROR|WARNING))|(?:USER_)?(?:NOTICE|DEPRECATED)|PARSE|STRICT|RECOVERABLE_ERROR|ALL)";
                        var E_OPER = "[&|^]";
                        var intRegex = new RegExp("^\\s*" + E_FLAG + "(?:\\s*" + E_OPER + "\\s*" + E_FLAG + ")*$");
                        if (/^-?\d+[kmg]?$/i.test(text) || intRegex.test(text)) {
                            valid = true;
                        } else {
                            valid = false;
                            valMsg = LOCALE.maketext("You must provide either an integer value, a [output,url,_1,shorthand byte,target,blank,title,shorthand byte documentation], or a [output,url,_2,predefined constant,target,blank,title,predefined constant documentation].", "http://php.net/manual/en/faq.using.php#faq.using.shorthandbytes", "http://php.net/manual/en/errorfunc.constants.php");
                        }
                    } else if (type === "float") {
                        if (/^-?\d+(?:\.\d*)?$/.test(text)) {
                            valid = true;
                        } else {
                            valid = false;
                            valMsg = LOCALE.maketext("You must provide a valid float value.");
                        }
                    }
                    return {
                        valid: valid,
                        valMsg: valMsg
                    };
                }
            };
        }]);
    }
);

/*
 * templates/multiphp_ini_editor/views/basicMode.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/basicMode',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "cjt/decorators/growlDecorator",
        "app/services/configService"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "basicMode",
            ["$scope", "$location", "$routeParams", "$timeout", "spinnerAPI", "alertService", "growl", "growlMessages", "configService", "PAGE",
                function($scope, $location, $routeParams, $timeout, spinnerAPI, alertService, growl, growlMessages, configService, PAGE) {

                // Setup data structures for the view
                    var alreadyInformed = false;
                    var infoGrowlHandle;
                    $scope.selectedVersion = "";
                    $scope.localeIsRTL = false;
                    $scope.loadingDirectiveList = false;
                    $scope.showEmptyMessage = false;
                    $scope.phpVersionsEmpty = true;
                    $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Not Available --[comment,used for highlight in select option]");

                    $scope.knobLabel = "\u00a0";

                    var resetForm = function() {

                        // Reset the directive list to empty.
                        $scope.directiveList = [];
                        $scope.showEmptyMessage = false;
                    };

                    $scope.loadDirectives = function() {
                        if ($scope.selectedVersion) {

                        // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();

                            spinnerAPI.start("loadingSpinner");
                            var version = $scope.selectedVersion;
                            $scope.loadingDirectiveList = true;
                            alreadyInformed = false;
                            return configService
                                .fetchBasicList(version)
                                .then(function(results) {

                                // Map the localized string for the directives' defaults
                                // to show them with the directive values.
                                    if (typeof (results.items) !== "undefined" && results.items.length > 0 ) {
                                        $scope.directiveList = results.items.map(function(item) {
                                            item.toggleValue = ( item.value === "On" ) ? true : false;
                                            var defaultPhpValue = item.default_value;
                                            if ( typeof item.cpanel_default !== "undefined" && item.cpanel_default !== null ) {
                                                defaultPhpValue = item.cpanel_default;
                                            }
                                            if ( item.type === "boolean" ) {
                                                defaultPhpValue = item.default_value === "1" ?
                                                    LOCALE.maketext("Enabled") : LOCALE.maketext("Disabled");
                                            }

                                            item.defaultText = LOCALE.maketext("[asis,PHP] Default: [output,class,_1,defaultValue]", defaultPhpValue);
                                            return item;
                                        });
                                    }
                                }, function(error) {
                                    growl.error(error);
                                    $scope.showEmptyMessage = true;
                                })
                                .then(function() {
                                    $scope.loadingDirectiveList = false;
                                    spinnerAPI.stop("loadingSpinner");
                                })
                                .finally(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.showEmptyMessage = $scope.selectedVersion !== "" && $scope.directiveList.length <= 0;
                                });
                        } else {
                            resetForm();
                        }
                    };

                    var informUser = function() {
                        if (!alreadyInformed) {
                            alreadyInformed = true;

                            growl.info(LOCALE.maketext("You must click “[_1]” to apply the new changes.", LOCALE.maketext("Apply")),
                                {
                                    onopen: function() {
                                        infoGrowlHandle = this;
                                    }
                                }
                            );
                        }
                    };

                    $scope.toggle_status = function(directive) {
                        if (directive.value === "On") {
                            directive.value = "Off";
                            directive.toggleValue = false;
                        } else {
                            directive.value = "On";
                            directive.toggleValue = true;
                        }
                        informUser();
                    };

                    $scope.directiveTextChange = function(directive) {
                        informUser();
                        var valInfo = configService.validateBasicDirective(directive.type, directive.value);
                        $scope.basicModeForm["txt" + directive.key].$setValidity("pattern", valInfo.valid);
                        directive.validationMsg = valInfo.valMsg;
                    };

                    $scope.disableApply = function() {
                        return ($scope.phpVersionsEmpty || !$scope.selectedVersion || !$scope.basicModeForm.$valid);
                    };

                    $scope.requiredValidation = function(directive) {
                        return (directive.type !== "string" && directive.type !== "boolean");
                    };

                    $scope.applyPhpSettings = function() {

                        if ($scope.basicModeForm.$valid) {

                            // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();
                            alreadyInformed = false;
                            if ( typeof infoGrowlHandle !== "undefined" ) {
                                infoGrowlHandle.destroy();
                            }
                            return configService.applySettings($scope.selectedVersion, $scope.directiveList)
                                .then(
                                    function(data) {
                                        if (data !== undefined) {
                                            growl.success(LOCALE.maketext("Successfully applied the settings to [asis,PHP] version “[_1]”.", $scope.selectedVersion));
                                        }
                                    }, function(error) {
                                        growl.error(error);
                                    });
                        }
                    };

                    var setDomainPhpDropdown = function(versionList) {

                        // versionList is sent to the function when the
                        // dropdown is bound the first time.
                        if (typeof (versionList) !== "undefined") {
                            $scope.phpVersions = versionList;
                        }

                        if ($scope.phpVersions.length > 0) {
                            $scope.phpVersionsEmpty = false;
                            $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Select a [asis,PHP] version --[comment,used for highlight in select option]");
                        } else {
                            $scope.phpVersionsEmpty = true;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {

                    // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        $scope.localeIsRTL = PAGE.locale_is_RTL ? true : false;

                        var versionListData = PAGE.php_versions;
                        var versionList = [];
                        if (versionListData.metadata.result) {

                        // Create a copy of the original list.
                            versionList = angular.copy(versionListData.data.versions);
                        } else {
                            growl.error(versionListData.metadata.reason);
                        }

                        // Bind PHP versions specific to domain dropdown list
                        setDomainPhpDropdown(versionList);
                    });
                }
            ]);

        return controller;
    }
);

/*
 * templates/multiphp_ini_editor/views/basicMode.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* global ace: false */

define(
    'app/views/editorMode',[
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "ace",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/decorators/growlDecorator",
        "app/services/configService"
    ],
    function(angular, _, $, LOCALE) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "editorMode",
            ["$scope", "$location", "$routeParams", "$timeout", "spinnerAPI", "alertService", "growl", "growlMessages", "configService", "PAGE",
                function($scope, $location, $routeParams, $timeout, spinnerAPI, alertService, growl, growlMessages, configService, PAGE) {
                    var alreadyInformed = false;
                    var infoGrowlHandle;
                    $scope.processingEditor = false;
                    $scope.showEmptyMessage = false;
                    $scope.contentIsEmpty = true;
                    $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Not Available --[comment,used for highlight in select option]");
                    var editor;

                    $scope.loadContent = function() {
                        if ($scope.selectedVersion) {

                            // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();

                            spinnerAPI.start("loadingSpinner");
                            var version = $scope.selectedVersion;
                            alreadyInformed = false;
                            editorInProcess(true);
                            return configService
                                .fetchContent(version)
                                .then(function(content) {
                                    if (content !== "") {
                                        $scope.contentIsEmpty = false;

                                        // Using jquery way of decoding the html content.
                                        // Tried to use '_' version of unescape method but it
                                        // did not decode encoded version of apostrophe (')
                                        // where the code is &#39;
                                        var htmlContent = $("<div/>").html(content).text();

                                        // Create Ace editor object if it's not yet created.
                                        if (typeof (editor) === "undefined") {
                                            editor = ace.edit("editor");

                                            // The below line is added to disable a
                                            // warning message as required by ace editor
                                            // script.
                                            editor.$blockScrolling = Infinity;
                                            editor.setShowPrintMargin(false);
                                        }

                                        // Bring the text area into focus and scroll to
                                        // the top of the INI document if a new one is loaded.
                                        editor.focus();
                                        editor.scrollToRow(0);

                                        // Set the editor color theme.
                                        editor.setTheme("ace/theme/chrome");

                                        var editSession = ace.createEditSession(htmlContent);
                                        editor.setSession(editSession);
                                        if (typeof (editSession) !== "undefined") {
                                            editSession.setMode("ace/mode/ini");
                                            editor.on("change", $scope.informUser);
                                        }
                                    } else {
                                        $scope.contentIsEmpty = true;
                                    }
                                }, function(error) {

                                    // failure
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "errorFetchDirectiveList"
                                    });
                                })
                                .then(function() {
                                    editorInProcess(false);
                                })
                                .finally(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.showEmptyMessage = !$scope.processingEditor && $scope.selectedVersion !== "" && $scope.contentIsEmpty;
                                });
                        } else {
                            resetForm();
                        }
                    };

                    $scope.informUser = function() {
                        if (!alreadyInformed) {
                            alreadyInformed = true;
                            growl.info(LOCALE.maketext("You must click “[_1]” to apply the new changes.", LOCALE.maketext("Save")),
                                {
                                    onopen: function() {
                                        infoGrowlHandle = this;
                                    }
                                }
                            );
                        }
                    };

                    $scope.save = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();
                        alreadyInformed = false;
                        if ( typeof infoGrowlHandle !== "undefined" ) {
                            infoGrowlHandle.destroy();
                        }
                        editorInProcess(true);
                        var changedContent = _.escape(editor.getSession().getValue());

                        return configService.saveIniContent($scope.selectedVersion, changedContent)
                            .then(
                                function(data) {
                                    if (typeof (data) !== "undefined") {
                                        growl.success(LOCALE.maketext("Successfully saved the changes."));
                                    }
                                }, function(error) {

                                    // escape the error text to prevent XSS attacks.
                                    growl.error(_.escape(error));
                                })
                            .then(function() {
                                editorInProcess(false);
                            });
                    };

                    var editorInProcess = function(processing) {
                        if (typeof (editor) !== "undefined") {
                            editor.setReadOnly(processing);
                        }

                        $scope.processingEditor = processing;
                    };

                    var resetForm = function() {
                        $scope.showEmptyMessage = false;
                        $scope.contentIsEmpty = true;
                    };

                    var setDomainPhpDropdown = function(versionList) {

                        // versionList is sent to the function when the
                        // dropdown is bound the first time.
                        if (typeof (versionList) !== "undefined") {
                            $scope.phpVersions = versionList;
                        }

                        if ($scope.phpVersions.length > 0) {
                            $scope.phpVersionsEmpty = false;
                            $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Select a [asis,PHP] version --[comment,used for highlight in select option]");
                        } else {
                            $scope.phpVersionsEmpty = true;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        var versionListData = PAGE.php_versions;
                        var versionList = [];
                        if (versionListData.metadata.result) {

                            // Create a copy of the original list.
                            versionList = angular.copy(versionListData.data.versions);
                        } else {
                            growl.error(versionListData.metadata.reason);
                        }

                        // Bind PHP versions specific to domain dropdown list
                        setDomainPhpDropdown(versionList);
                    });
                }]);

        return controller;
    }
);

/*
* templates/multiphp_ini_editor/index.js            Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngAnimate"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm",
                "whm.multiPhpIniEditor.configService"

            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/basicMode",
                    "app/views/editorMode",
                    "cjt/directives/actionButtonDirective"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    // Setup Routing
                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/basic", {
                                controller: "basicMode",
                                templateUrl: CJT.buildFullPath("multiphp_ini_editor/views/basicMode.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editor", {
                                controller: "editorMode",
                                templateUrl: CJT.buildFullPath("multiphp_ini_editor/views/editorMode.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/basic"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$location", "growlMessages", function($rootScope, $location, growlMessages) {

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                            growlMessages.destroyAllMessages();
                        });
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

