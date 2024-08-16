/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/constants.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('app/constants',["cjt/util/locale"], function(LOCALE) {
    "use strict";

    var DEFAULT_PRIMARY_DARK = "#08193E";  // $cp-midnight-express from /usr/local/cpanel/base/frontend/jupiter/base_styles/00_configuration/_cp_colors.scss
    var DEFAULT_PRIMARY_LIGHT = "#ffffff"; // $cp-white            from /usr/local/cpanel/base/frontend/jupiter/base_styles/00_configuration/_cp_colors.scss

    return {

        // Image
        EMBEDDED_SVG: "data:image/svg+xml;base64,",
        EMBEDDED_ICO: "data:image/x-icon;base64,",
        DATA_URL_PREFIX_REGEX: /^data:[^,]*,/,

        // Colors - It would be nice to figure out a way to load these from the scss file, but I cant see a good way without
        DEFAULT_PRIMARY_DARK: DEFAULT_PRIMARY_DARK,
        DEFAULT_PRIMARY_LIGHT: DEFAULT_PRIMARY_LIGHT,
        DEFAULT_COLORS: {
            primary: DEFAULT_PRIMARY_DARK,
        },

        // File upload sizes
        MAX_FILE_SIZE: 100 * 1000,  // 100 kilobytes

        // Tabs
        GENERAL_TABS_INFO: {
            logos: LOCALE.maketext("Logos"),
            colors: LOCALE.maketext("Colors"),
            favicon: LOCALE.maketext("Favicon"),
            links: LOCALE.maketext("Links"),
            "public-contact": LOCALE.maketext("Public Contact"),
        },

        JUPITER_TAB_ORDER: [
            "logos",
            "colors",
            "favicon",
            "links",
            "public-contact",
        ],

        JUPITER_TAB_INDEX: {
            "logos": 3,
            "colors": 4,
            "favicon": 5,
            "links": 6,
            "public-contact": 10,
        },

        // Routing
        DEFAULT_THEME: "jupiter",
        DEFAULT_ROUTE: "logos",
    };
});

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/savedService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* jshint -W089 */
/* jshint -W018 */

define(
    'app/services/savedService',[

        // Libraries
        "angular",
    ],
    function(angular, API, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("customize.services.savedService", []);

        app.factory("savedService", [function() {
            var tabs = {};

            var DEFAULT = {
                dirty: false,
            };

            // return the factory interface
            return {

                /**
                 * Register all the participating tabs
                 *
                 * @param {string[]} tabNames
                 */
                registerTabs: function(tabNames) {
                    tabNames.forEach(function(tabName) {
                        tabs[tabName] = angular.copy(DEFAULT);
                    });
                },

                /**
                 * Check if the tab or tabs need to be saved. If you provide a `tabName` it
                 * only looks at the one tab, if not it checks all the registered tabs.
                 *
                 * NOTE: Not all tabs are registered currently. Unregisted tabs return false
                 * since they are not yet participating in this system.
                 *
                 * @param {string} tabName
                 * @returns {boolean} true if you need to save something, false otherwise.
                 */
                needToSave: function(tabName) {
                    if (!tabName) {

                        // Check all the tabs
                        return Object.keys(tabs).some(function(tabName) {
                            return tabs[tabName] ? tabs[tabName].dirty : false;
                        });
                    } else {

                        // Check just the requested tab
                        return tabs[tabName] ? tabs[tabName].dirty : false;
                    }
                },

                /**
                 * Mark a tab state:
                 *
                 *   * dirty = true, need to save it.
                 *   * dirty = false, its saved already.
                 *
                 * @param {string} tabName
                 * @param {boolean} dirty
                 */
                update: function(tabName, dirty) {
                    if (tabs[tabName]) {
                        tabs[tabName].dirty = dirty;
                    }
                },
            };
        }]);
    });

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/beforeUnloadService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('app/services/beforeUnloadService',[
    "angular",
],
function(angular) {
    "use strict";

    /*
     * This service is used to send events when the window
     * onbeforeunload and onunload event happen.
     *
     * The service will broadcast the following events:
     *
     * onBeforeUnload - application code can register for this event on the scope. This
     * event can be used to prevent the unload using the `event.preventDefault()` technique.
     * Note, not all browsers will show the unload popup. Some also wont show it unless the
     * user has interacted with the form. Some browser will not use the custom message.
     *
     * onUnload - application code can register for this event on the scope. It can be used
     * to clean up any resources or cancel outstanding remote calls. You can not cancel the
     * unload from this event.
     */

    angular.module("customize.services.beforeUnloadService", [])
        .factory("beforeUnload", [ "$rootScope", "$window", function($rootScope, $window) {

            /**
             * Handler for the browser onbeforeunload event.
             *
             * @param {Event} e
             * @returns {string|undefined} - A message to show the user when deciding if they want to cancel the unload.
             */

            $rootScope.doBeforeUnload = function(e) {
                var config = {};

                /**
                 * @typedef {Config}
                 * @property {string} prompt - the propt to tell the user.
                 */
                var event = $rootScope.$broadcast("onBeforeUnload", config);
                if (event.defaultPrevented) {
                    e.preventDefault();

                    // Note: Some browsers will not show this message, but instead have their own.
                    e.returnValue = config.prompt || ""; // For some Chrome browsers
                    return config.prompt;
                } else {
                    delete e["returnValue"]; // For some Chrome browsers
                    return false;
                }
            };


            /**
             * Handler for the browser unload event
             */
            $rootScope.doUnload = function() {
                $rootScope.$broadcast("onUnload");
            };

            $window.addEventListener("beforeunload", $rootScope.doBeforeUnload);
            $window.addEventListener("onunload", $rootScope.doUnload);

            return {};
        } ] )
        .run(["beforeUnload", function(beforeUnload) {

        // Must invoke the service at least once
        } ] );
});

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileReader.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/directives/fileReader',[
        "angular",
        "cjt/util/locale",
        "app/constants",
    ],
    function(angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.directives.fileReader", []);

        module.directive("fileReader", [
            "$q",
            function($q) {
                return {
                    restrict: "A",
                    require: [ "?ngModel" ],
                    priority: 20,
                    link: function(scope, element, attrs, controllers) {
                        var ngModel = controllers[0];

                        // To use this attribute directive a parent element must:
                        // * have an ngModel attribute
                        // * be an <input> element
                        // * have an type attribute of 'file'
                        if (!ngModel || element[0].tagName !== "INPUT" || !attrs["type"] || attrs["type"] !== "file") {
                            return;
                        }

                        ngModel.$render = function() {};

                        /**
                         * Helper used to mock behavior in tests
                         * @param {HtmlFileInput} el
                         * @returns {File}
                         */
                        scope._getFiles = function(el) {
                            return el.files;
                        };

                        /**
                         * Helper used to mock behavior in tests
                         * @returns {number}
                         */
                        scope._getMaxSize = function() {
                            return CONSTANTS.MAX_FILE_SIZE;
                        };

                        /**
                         * Merge file data to the model object.
                         *
                         * @param {ngModelController} ngModel
                         * @param {File} file
                         * @param {string} data
                         * @returns {Object} The updated model.
                         */
                        scope._mergeToModel = function(ngModel, file, data) {
                            var model = angular.copy(ngModel.$modelValue);
                            model.filename = file.name;
                            model.size = file.size;
                            model.type = file.type;
                            model.data = data;

                            delete model.error;
                            delete model.errorKey;
                            return model;
                        };

                        /**
                         * Update the model with the error information.
                         *
                         * @param {Object} model - Model to store the data into.
                         * @param {String} message - Human readable message
                         * @param {String} key - Machine identifier for the error.
                         */
                        scope._setModelError = function(model, message, key) {
                            model.error = message;
                            model.errorKey = key;
                        };

                        /**
                         * Converts a file into a base64 encoded string.
                         *
                         * @async
                         * @param {File} file - As defined here: https://developer.mozilla.org/en-US/docs/Web/API/File
                         * @returns {string} The base64 encoded file contents.
                         */
                        scope._toBase64 = function(file) {
                            var deferred = $q.defer();
                            var maxSize = scope._getMaxSize();
                            var model;

                            if (file.size > maxSize) {

                                // We resolve instead of reject to allow the validation to get all
                                // the info and make decisions based on it. We only exclude the costly
                                // .data property
                                model = scope._mergeToModel(ngModel, file, "");
                                scope._setModelError(model, LOCALE.maketext("The file is larger than the maximum of [numf,_1] kilobytes.", maxSize), "maxsize");
                                deferred.resolve(model);
                                return deferred.promise;
                            }

                            var reader = new FileReader();
                            reader.addEventListener("loadend", function(e) {
                                scope.$apply(function() {
                                    model = scope._mergeToModel(ngModel, file, e.target.result);
                                    deferred.resolve(model);
                                });
                            });

                            reader.addEventListener("error", function(e) {
                                scope.$apply(function() {

                                    // We resolve instead of reject to allow the validation to get all
                                    // the info and make decisions based on it. We only exclude the costly
                                    // .data property
                                    model = scope._mergeToModel(ngModel, file, "");
                                    scope._setModelError(model, e && e.target ? e.target.error : LOCALE.maketext("An unknown error occurred while reading the file contents."), "readFailed");
                                    deferred.resolve(model);
                                });
                            });

                            try {
                                reader.readAsDataURL(file);
                            } catch (error) {

                                // Catch any synchronous errors.

                                // We resolve instead of reject to allow the validation to get all
                                // the info and make decisions based on it. We only exclude the costly
                                // .data property
                                model = scope._mergeToModel(ngModel, file, "");
                                scope._setModelError(model, error ? error : LOCALE.maketext("An unknown error occurred while reading the file contents."), "readFailed");
                                deferred.resolve(model);
                            }

                            return deferred.promise;
                        };

                        element.bind("change", function(e) {
                            scope.$apply(function() {
                                var el = e.target;
                                var files = scope._getFiles(el);
                                if (!files || !files.length) {
                                    return;
                                }

                                var file = files[0];
                                if (file && file.size !== 0) {
                                    scope._toBase64(file)
                                        .then(function(value) {
                                            ngModel.$setViewValue(value);  // NOTE: This will trigger the $parsers above.
                                        });
                                }
                                return;
                            });
                        });
                    },
                };
            },
        ]);
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileType.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('app/directives/fileType',[
    "angular",
], function(angular) {
    "use strict";

    var module = angular.module("customize.directives.fileType", []);

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    module.directive("fileType", [function() {
        function checkType(file, types) {
            return types.some(function(type) {
                return file.type === type;
            });
        }
        return {
            restrict: "A",
            require: "ngModel",
            link: function link($scope, $element, $attrs, $ngModelCtrl) {
                $element.bind("change", function() {
                    var file = this.files[0];
                    if (file && !checkType(file, $scope.$eval($attrs.fileType))) {
                        $ngModelCtrl.$setValidity("filetype", false);
                    } else {
                        $ngModelCtrl.$setValidity("filetype", true);
                    }
                });
            },
        };
    }]);
});

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/triggerFor.js
#                                                  Copyright 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define('app/directives/triggerFor',[
    "angular",
], function(angular) {
    "use strict";

    var module = angular.module("customize.directives.triggerFor", []);

    // This directive will trigger a "click" event on another element when the linked element is clicked.
    module.directive("triggerFor", [function() {
        return {
            restrict: "A",
            link: function link($scope, $element, $attrs) {
                $element.bind("click", function() {
                    document.querySelector("#" + $attrs.triggerFor).click();
                });
            },
        };
    }]);
});

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileUpload.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/directives/fileUpload',[
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "uiBootstrap",
        "app/directives/fileReader",
        "app/directives/fileType",
        "app/directives/triggerFor",
    ],
    function(angular, LOCALE, CJT) {
        "use strict";

        var module = angular.module("customize.directives.fileUpload", [
            "customize.directives.fileReader",
            "customize.directives.fileType",
            "customize.directives.triggerFor",
            "ui.bootstrap",
        ]);

        module.directive("cpFileUpload",
            [
                "$uibModal",
                function($uibModal) {
                    var TEMPLATE_PATH = "directives/fileUpload.phtml";
                    var RELATIVE_PATH = "templates/cpanel_customization/" + TEMPLATE_PATH;

                    return {
                        replace: true,
                        require: [ "^form", "ngModel" ],
                        restrict: "E",
                        scope: {
                            id: "@id",
                            title: "@title",
                            browseButtonLabel: "@browseButtonLabel",
                            deleteButtonTitle: "@deleteButtonTitle",
                            confirmDeleteMessage: "@confirmDeleteMessage",
                            previewTitle: "@previewTitle",
                            help: "@help",
                            fileTypeError: "@fileTypeError",
                            fileEmptyError: "@fileEmptyError",
                            fileMaxSizeError: "@fileMaxSizeError",
                            model: "=ngModel",
                            types: "=mimeTypes",
                            previewBgColor: "=previewBgColor",
                            onDelete: "&onDelete",
                            onChange: "&onChange",
                            onReset: "&onReset",
                            inputClasses: "@inputClass",
                            previewClasses: "@previewClass",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs, controllers) {
                            scope.LOCALE = LOCALE;
                            var formController = controllers[0];
                            var modelController = controllers[1];

                            if (!scope.inputClasses) {
                                scope.inputClasses = "col-xs-12 col-sm-8 col-md-8 col-lg-6";
                            }

                            if (!scope.previewClasses) {
                                scope.previewClasses = "col-xs-12 col-sm-4 col-md-4 col-lg-4";
                            }

                            /**
                             * Generate a complete field name for a field in the upload form partial.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {string}
                             */
                            scope.field = function(field) {
                                return "file_upload_" + field;
                            };

                            /**
                             * Check if the given form field is pritine.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {boolean} - true if its pristine, false otherwise.
                             */
                            scope.isPristine = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$pristine;
                                }
                                return true;
                            };

                            /**
                             * Check if the given form field is invalid.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {boolean} - true if its invalid, false otherwise.
                             */
                            scope.isInvalid = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$invalid;
                                }
                                return true;
                            };

                            /**
                             * Checks if the given field has the given error.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @param {string} kind - name of the error you are looking for.
                             * @returns {boolean} - the error object if present, undefined otherwise.
                             */
                            scope.errors = function(field, kind) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$error[kind];
                                }
                                return;
                            };

                            /**
                             * Set the field to pristine.
                             *
                             * @param {string} field
                             */
                            scope.setPristine = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    f.$setPristine();
                                }
                                return;
                            };

                            /**
                             * Creates a clean copy of the model.
                             *
                             * @param {FileModel} model
                             * @returns {FileModel}
                             */
                            function cleanCopy(original) {
                                var model = angular.copy(original);
                                model.data = "";
                                model.filename = "";
                                model.size = 0;
                                model.type = "";
                                delete model.error;
                                delete model.errorType;
                                return model;
                            }

                            /**
                             * @typedef FileModel
                             * @property {string} filename - name of the file to display
                             * @property {string} data - base 64 encoded file contents
                             * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                             * @property {string} name - name of the property
                             */

                            /**
                             * Initiate a delete file operation
                             * @param {FileModel} model - the data model
                             */
                            scope.delete = function(model) {
                                scope.deleteLoading = true;
                                var promise = scope.onDelete(model);
                                if (promise && promise.then) {
                                    promise.then(function() {
                                        scope.deleteLoading = false;
                                        scope.model = cleanCopy(modelController.$modelValue);
                                        scope.setPristine(scope.id + "_file");
                                    });
                                } else {
                                    scope.deleteLoading = false;
                                    scope.model = cleanCopy(modelController.$modelValue);
                                    scope.setPristine(scope.id + "_file");
                                }
                            };

                            /**
                             * Confirms deleting
                             *
                             * @method confirmDelete
                             * @param {FileModel} model - the data model
                             */
                            scope.confirmDelete = function(model) {
                                if (model.saved) {

                                    var TEMPLATE_PATH = "directives/fileConfirmUploadDelete.phtml";
                                    var RELATIVE_PATH = "templates/cpanel_customization/" + TEMPLATE_PATH;

                                    $uibModal.open({
                                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                                        size: "sm",
                                        controller: [
                                            "$scope",
                                            "$uibModalInstance",
                                            function($scope, $uibModalInstance) {
                                                $scope.message = scope.confirmDeleteMessage;
                                                $scope.LOCALE = LOCALE;

                                                $scope.close = function close(confirmed) {
                                                    $uibModalInstance.close(confirmed);
                                                };
                                            },
                                        ],
                                    }).result.then(function(confirmed) {
                                        if (confirmed) {
                                            scope.delete(model);
                                        }
                                    });
                                } else {
                                    scope.model = cleanCopy(scope.model);

                                    var elId = scope.field(scope.id + "_file");

                                    var fileEl = angular.element("#" + elId);
                                    fileEl.val(null);

                                    // Clear the error state.
                                    formController[elId].$setValidity("fileSize", true);
                                    formController[elId].$setValidity("fileMaxSize", true);
                                    formController[elId].$setValidity("filetype", true);
                                    formController[elId].$setPristine();

                                    scope.onReset(scope.model);
                                }
                            };

                            scope.change = function() {
                                scope.onChange(scope.model);
                            };
                        },
                    };
                },
            ]
        );
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/customizeService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* jshint -W089 */
/* jshint -W018 */

define(
    'app/services/customizeService',[

        // Libraries
        "angular",
        "cjt/util/locale",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "app/constants",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        "cjt/services/APICatcher",
    ],
    function(angular, LOCALE, API, APIREQUEST, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.services.customizeService", [
            "cjt2.services.apicatcher",
            "cjt2.services.api",
        ]);

        module.factory("customizeService", ["APICatcher", "$q", function(APICatcher, $q) {

            // return the factory interface
            return {

                /**
                 * @typedef CustomizationModel
                 * @property {Object} brand - properties related to branding a cPanel instanance.
                 * @property {Object} brand.logo - properties related to the logos used in the UI.
                 * @property {string} brand.logo.forLightBackground - base64 encoded logo used when the background color is light.
                 * @property {string} brand.logo.forDarkBackground - base64 encoded logo used when the background color is dark.
                 * @property {string} brand.logo.description - title used with the logo for assistive technology
                 * @property {Object} brand.colors - dictionary of customizable colors for the UI.
                 * @property {string} brand.colors.primary - hex color used in primary UI features.
                 * @property {string} brand.colors.link - hex color used in links.
                 * @property {string} brand.colors.accent - hex color used in accents.
                 * @property {string} brand.favicon - base64 encoded favicon.
                 * @property {Object} help - online help related properties.
                 * @property {string} help.url - URL to the online help for a company.
                 * @property {Object} documentation - documenation related properties.
                 * @property {string} documentation.url - URL to the custom documentation site for a company.
                 */

                /**
                 * Update the customization options for jupiter based themes
                 *
                 * @async
                 * @param {CustomizationModel} customizations - the updated customizations to store on the server.
                 * @param {string} theme - the theme name to which the customization is updated. Defaults to CONSTANTS.DEFAULT_THEME.
                 */
                update: function(customizations, theme) {
                    if (angular.isUndefined(customizations)) {
                        return $q.reject(LOCALE.maketext("The customization parameter is missing or not an object."));
                    }

                    var apicall = new APIREQUEST.Class().initialize(
                        "", "update_customizations", {
                            application: "cpanel",
                            theme: theme || CONSTANTS.DEFAULT_THEME,
                            data: JSON.stringify(customizations),
                        });

                    return APICatcher.promise(apicall);
                },

                /**
                 * Delete a path in the the customization data.
                 *
                 * @async
                 * @param {string} path - optional, The JSONPath to delete
                 * @param {string} theme - the theme name to which the customization is updated. Defaults to CONSTANTS.DEFAULT_THEME.
                 */
                delete: function(path, theme) {
                    var apicall = new APIREQUEST.Class().initialize(
                        "", "delete_customizations", {
                            application: "cpanel",
                            theme: theme || CONSTANTS.DEFAULT_THEME,
                            path: path,
                        });

                    return APICatcher.promise(apicall);
                },

                /**
                 * For the provided tabInfo, this method retrieves the tabs list and their associcated information.
                 *
                 * @param {Object} tabInfo - The theme specific tab information.
                 */
                getThemeTabList: function(tabInfo) {
                    var themeTabs = tabInfo.order.map(tab => {
                        return {
                            key: tab, name: CONSTANTS.GENERAL_TABS_INFO[tab], index: tabInfo.index[tab],
                        };
                    });
                    return themeTabs;
                },
            };
        }]);
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/logoController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

define(
    'app/views/jupiter/logoController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "app/constants",
        "cjt/directives/autoFocus",
        "cjt/decorators/growlDecorator",
        "app/directives/fileUpload",
        "app/services/customizeService",
        "app/services/savedService",
    ],
    function(_, angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.views.logoController", [
            "customize.services.customizeService",
            "customize.directives.fileUpload",
            "customize.services.savedService",
        ]);

        var controller = module.controller(
            "logoController", [
                "$scope",
                "customizeService",
                "savedService",
                "growl",
                "growlMessages",
                "PAGE",
                function($scope, customizeService, savedService, growl, growlMessages, PAGE) {
                    $scope.saving = false;

                    // Load the prefetched data from the PAGE object.
                    var lightLogo = PAGE.data.jupiter.brand.logo.forLightBackground;
                    var darkLogo = PAGE.data.jupiter.brand.logo.forDarkBackground;
                    var description = PAGE.data.jupiter.brand.logo.description;

                    /**
                     * @typedef FileModel
                     * @property {string} filename - name of the file to display
                     * @property {string} data - base 64 encoded file contents
                     * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                     * @property {string} name - name of the property
                     */

                    /**
                     * @typedef LogosModel
                     * @property {FileModel} forLightBackground - storage for the logo use on light backgrounds.
                     * @property {FileModel} forDarkBackground - storage for the logo used on dark backgrounds.
                     * @property {string} description - description for use with the logos as the title property.
                     */
                    $scope.model = {
                        forLightBackground: {
                            data: lightLogo ? CONSTANTS.EMBEDDED_SVG + lightLogo : "",
                            filename: lightLogo ? "logo-light.svg" : "",
                            saved: !!lightLogo,
                            name: "forLightBackground",
                        },
                        forDarkBackground: {
                            data: darkLogo ? CONSTANTS.EMBEDDED_SVG + darkLogo : "",
                            filename: darkLogo ? "logo-dark.svg" : "",
                            saved: !!darkLogo,
                            name: "forDarkBackground",
                        },
                        description: description || "",
                    };

                    $scope.MAX_FILE_SIZE = CONSTANTS.MAX_FILE_SIZE;
                    $scope.LOCALE = LOCALE;

                    // Watch for changes
                    $scope.$watch("model.forLightBackground", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, true);

                    $scope.$watch("model.forDarkBackground", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, true);

                    $scope.$watch("model.description", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, false);

                    /**
                     * @typedef backgroundColors
                     * @property {string} primaryDark - the background color the logo in full screen.
                     * @property {string} primaryLight - the background color for the logo in mobile.
                     */
                    $scope.backgroundColors = {
                        primaryDark: PAGE.data.jupiter.brand.colors.primary || CONSTANTS.DEFAULT_PRIMARY_DARK,

                        // NOTE: There does not seem to be an override for mobile background for the logo
                        primaryLight: CONSTANTS.DEFAULT_PRIMARY_LIGHT,
                    };

                    /**
                     * Save the logo data from the tab.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.save = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if (!$formCtrl.$valid) {
                            growl.error(LOCALE.maketext("The current customization is invalid."));
                            return;
                        }

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;

                        var forDarkBackground = $scope.model.forDarkBackground.data;
                        if (forDarkBackground) {
                            forDarkBackground = forDarkBackground.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");
                        }
                        var forLightBackground = $scope.model.forLightBackground.data;
                        if (forLightBackground) {
                            forLightBackground = forLightBackground.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");
                        }

                        customizeService.update({
                            brand: {
                                logo: {
                                    forLightBackground: forLightBackground,
                                    forDarkBackground: forDarkBackground,
                                    description: $scope.model.description,
                                },
                            },
                        }).then(function(update) {
                            if (forDarkBackground) {
                                $scope.model.forDarkBackground.filename = "logo-dark.svg";
                                $scope.model.forDarkBackground.saved = true;

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo.forDarkBackground = forDarkBackground;
                            }
                            if (forLightBackground) {
                                $scope.model.forLightBackground.filename = "logo-light.svg";
                                $scope.model.forLightBackground.saved = true;

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo.forLightBackground = forLightBackground;
                            }

                            // Update the initial data
                            PAGE.data.jupiter.brand.logo.description = $scope.model.description;

                            $formCtrl.$setPristine();
                            savedService.update("logos", false);

                            growl.success(LOCALE.maketext("The system successfully updated the logos."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update your logos."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Evaluate the state of the inputs and update the $pristine state of the form.
                     *
                     * NOTE:
                     * angular.js does not reevalute the form.$isPristine flag when the child inputs
                     * are set to pristine individually. We must loop over the list of controls ourselves
                     * and the set this property.
                     * @param {FormController} $formCtrl
                     */
                    var updateFormState = function($formCtrl) {
                        var controls = ["file_upload_logo_dark_file", "file_upload_logo_light_file", "icon_description"];
                        var isPristine = true; // Assume pristine, unless there is evidence otherwise.
                        controls.forEach(function(inputName) {
                            if ($formCtrl[inputName].$dirty) {
                                isPristine = false;
                            }
                        });
                        if (isPristine) {
                            $formCtrl.$setPristine();
                        }
                    };

                    /**
                     * Reset the logo to a pristine state after a delete before saving.
                     *
                     * @param {FormController} $formCtrl
                     * @param {string} which
                     */
                    $scope.reset = function($formCtrl, which) {
                        growlMessages.destroyAllMessages();
                        switch (which) {
                            case "forDarkBackground":
                                $formCtrl.file_upload_logo_dark_file.$setPristine();
                                break;
                            case "forLightBackground":
                                $formCtrl.file_upload_logo_light_file.$setPristine();
                                break;
                        }
                        updateFormState($formCtrl);
                        savedService.update("logos", $formCtrl.$dirty);
                    };

                    /**
                     * Remove the specific logo from the
                     * @param {FormController} $formCtrl
                     * @param {string} which - the name of the image field to delete
                     */
                    $scope.delete = function($formCtrl, which) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;
                        return customizeService.delete("brand.logo." + which)
                            .then(function(update) {
                                $scope.model[which].saved = false;
                                $scope.model[which].data = "";
                                $scope.model[which].filename = "";

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo[which] = "";

                                // Reset the part of the form that was persisted.
                                switch (which) {
                                    case "forDarkBackground":
                                        $formCtrl.file_upload_logo_dark_file.$setPristine();
                                        break;
                                    case "forLightBackground":
                                        $formCtrl.file_upload_logo_light_file.$setPristine();
                                        break;
                                }
                                savedService.update("logos", $formCtrl.$dirty);

                                growl.success(LOCALE.maketext("The system successfully removed the logo."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to remove the logo."));
                            })
                            .finally(function() {
                                $scope.saving = false;
                            });
                    };
                },
            ]
        );

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/faviconController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

define(
    'app/views/jupiter/faviconController',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "app/constants",
        "cjt/decorators/growlDecorator",
        "app/directives/fileUpload",
        "app/services/customizeService",
        "app/services/savedService",
    ],
    function(_, angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.views.faviconController", [
            "customize.directives.fileUpload",
            "customize.services.customizeService",
            "customize.services.savedService",
            "customize.directives.fileUpload",
        ]);

        // set up the controller
        var controller = module.controller(
            "faviconController", [
                "$scope",
                "customizeService",
                "savedService",
                "growl",
                "growlMessages",
                "PAGE",
                function($scope, customizeService, savedService, growl, growlMessages, PAGE) {

                    $scope.saving = false;
                    $scope.MAX_FILE_SIZE = CONSTANTS.MAX_FILE_SIZE;
                    $scope.LOCALE = LOCALE;

                    // Load the prefetched data from the PAGE object.
                    var favicon = PAGE.data.jupiter.brand.favicon;

                    /**
                     * @typedef FileModel
                     * @private
                     * @property {string} filename - name of the file to display
                     * @property {string} data - base 64 encoded file contents
                     * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                     */

                    /**
                     * @typedef FaviconModel
                     * @property {FileModel} favicon - storage for the favicon for the site.
                     * @property {FileModel} forDarkBackground - storage for the logo used on dark backgrounds.
                     * @property {string} description - description for use with the logos as the title property.
                     */
                    $scope.model = {
                        favicon: {
                            data: favicon ? CONSTANTS.EMBEDDED_ICO + favicon : "",
                            filename: favicon ? "favicon.ico" : "",
                            saved: !!favicon,
                        },
                    };

                    // Watch for changes
                    $scope.$watch("model.favicon", function() {
                        savedService.update("favicon", $scope.customization.$dirty);
                    }, true);


                    /**
                     * Save the favicon data from the tab.
                     *
                     * @async
                     * @param {FormController} $formCtrl
                     */
                    $scope.save = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if (!$formCtrl.$valid) {
                            growl.error(LOCALE.maketext("The current customization is invalid."));
                            return;
                        }

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;

                        var favicon = $scope.model.favicon.data.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");

                        return customizeService.update({
                            brand: {
                                favicon: favicon,
                            },
                        }).then(function(update) {
                            $scope.model.favicon.filename = "favicon.ico";
                            $scope.model.favicon.saved = true;

                            // Update the initial data
                            PAGE.data.jupiter.brand.favicon = favicon;

                            $formCtrl.$setPristine();
                            savedService.update("favicon", false);

                            growl.success(LOCALE.maketext("The system successfully updated the favicon."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update the favicon."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Reset the favicon to a pristine state after a delete before saving.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.reset = function($formCtrl) {
                        growlMessages.destroyAllMessages();
                        $formCtrl.file_upload_favicon_file.$setPristine();
                        savedService.update("favicons", false);
                    };

                    /**
                     * Remove the favorite icon from the customizations.
                     *
                     * @param {FormController} $formCtrl - the file to delete from the persistance layer.
                     */
                    $scope.delete = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;
                        return customizeService.delete("brand.favicon")
                            .then(function(update) {
                                $scope.model.favicon.saved = false;
                                $scope.model.favicon.data = "";
                                $scope.model.favicon.filename = "";

                                // Update the initial data
                                PAGE.data.jupiter.brand.favicon = "";

                                $formCtrl.$setPristine();
                                savedService.update("favicon", false);

                                growl.success(LOCALE.maketext("The system successfully removed the custom favicon and restored the default [asis,cPanel] favicon."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to remove the custom favicon."));
                            })
                            .finally(function() {
                                $scope.saving = false;
                            });
                    };
                },
            ]
        );

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/linksController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

define('app/views/jupiter/linksController',[
    "lodash",
    "angular",
    "cjt/util/locale",
    "cjt/directives/autoFocus",
    "cjt/decorators/growlDecorator",
    "app/services/customizeService",
    "app/services/savedService",
], function(_, angular, LOCALE) {
    "use strict";

    var module = angular.module("customize.views.linksController", [
        "customize.services.customizeService",
        "customize.services.savedService",
    ]);

    var controller = module.controller("linksController", [
        "$scope",
        "customizeService",
        "savedService",
        "growl",
        "growlMessages",
        "PAGE",
        function(
            $scope,
            customizeService,
            savedService,
            growl,
            growlMessages,
            PAGE
        ) {
            $scope.saving = false;

            $scope.urlRegex =
                /^(https?):\/\/(?:[^:@]+(?::[^@]+)?@)?(?:[^\s:/?#]+|\[[a-f\\d:]+])(?::\\d+)?(?:\/[^?#]*)?(?:\\?[^#]*)?(?:#.*)?$/i;

            // Preload links
            $scope.model = {
                help: PAGE.data.jupiter.help
                    ? angular.copy(PAGE.data.jupiter.help)
                    : { url: "" },
                documentation: PAGE.data.jupiter.documentation
                    ? angular.copy(PAGE.data.jupiter.documentation)
                    : { url: "" },
            };

            // Save initial values
            $scope.initialHelpLink = $scope.model.help["url"];
            $scope.initialDocumentationLink = $scope.model.documentation["url"];

            // Watch for changes
            $scope.$watchGroup(["model.help.url", "model.documentation.url"], function(newValues) {
                var helpLinkChanged = newValues[0] !== $scope.initialHelpLink;
                var documentationLinkChanged = newValues[1] !== $scope.initialDocumentationLink;

                // If the links match their original state, make the form pristine again
                if (!helpLinkChanged && !documentationLinkChanged) {
                    growlMessages.destroyAllMessages();
                    savedService.update("links", false);
                    $scope.customization.$setPristine();
                } else {
                    savedService.update("links", $scope.customization.$dirty);
                }

            }, false);

            /**
             * Saves changes to branding customization
             * Persist the customization form if it is valid
             * @method save
             * @param {Object} $formCtrl Form control
             */
            $scope.save = function($formCtrl) {
                growlMessages.destroyAllMessages();

                if (!$formCtrl.$valid) {
                    growl.error(
                        LOCALE.maketext("The current customization is invalid.")
                    );
                    return;
                }

                if ($scope.saving) {
                    growl.warning(
                        LOCALE.maketext(
                            "The system is busy. Try again once the current operation is complete."
                        )
                    );
                    return;
                }

                $scope.saving = true;
                customizeService
                    .update({
                        documentation: {
                            url: $scope.model.documentation.url,
                        },
                        help: {
                            url: $scope.model.help.url,
                        },
                    })
                    .then(function(response) {

                        // For subsequent loads of links tab, we need to update PAGE to reflect changes
                        PAGE.data.jupiter.documentation.url =
                            $scope.model.documentation.url;
                        PAGE.data.jupiter.help.url = $scope.model.help.url;

                        $formCtrl.$setPristine();
                        savedService.update("links", false);

                        growl.success(
                            LOCALE.maketext(
                                "The system successfully updated your links."
                            )
                        );
                    })
                    .catch(function(error) {
                        growl.error(
                            LOCALE.maketext(
                                "The system failed to update your links."
                            )
                        );
                    })
                    .finally(function() {
                        $scope.saving = false;
                    });
            };
        },
    ]);

    return controller;
});

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/colorsController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

require.config({
    paths: {
        "jquery-minicolors": "../../../libraries/jquery-minicolors/2.1.7/jquery.minicolors",
        "angular-minicolors": "../../../libraries/angular-minicolors/0.0.11/angular-minicolors",
    },
    shims: {
        "jquery-minicolors": {
            depends: [ "jquery" ],
        },
        "angular-minicolors": {
            depends: [ "jquery-minicolors" ],
        },
    },
});

define(
    'app/views/jupiter/colorsController',[
        "lodash",
        "angular",
        "jquery",
        "app/constants",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "angular-minicolors",
    ],
    function(_, angular, jquery, CONSTANTS, LOCALE) {
        "use strict";

        var module = angular.module("customize.views.colorsController", [
            "customize.services.customizeService",
            "minicolors",
        ]);

        module.config([
            "minicolorsProvider",
            function(minicolorsProvider) {
                angular.extend(minicolorsProvider.defaults, {
                    control: "wheel",
                    position: "bottom left",
                    letterCase: "uppercase",
                    theme: "bootstrap",
                });
            }]
        );

        // set up the controller
        var controller = module.controller(
            "colorsController", [
                "$scope",
                "customizeService",
                "growl",
                "growlMessages",
                "savedService",
                "PAGE",
                function($scope, customizeService, growl, growlMessages, savedService, PAGE) {
                    $scope.saving = false;
                    $scope.restoring = false;
                    $scope.hexColorRegex = "^#[0-9A-Fa-f]{6}";

                    /**
                     * @typedef ColorBrandPartial
                     * @type {object}
                     * @property {object} brand
                     * @property {ColorsModel} brand.colors
                     */

                    /**
                     * @typedef ColorsModel
                     * @type {object}
                     * @property {string} primary - CSS color for the left menu
                     * @property {string} link - CSS color for links - NOT IMPLEMENT YET
                     * @property {string} accent - CSS color for various accents in the product. - NOT IMPLEMENT YET
                     */

                    // Load the prefetched data from the PAGE object.
                    $scope.model = {
                        colors: {},
                        defaults: angular.copy(CONSTANTS.DEFAULT_COLORS),
                    };

                    $scope.$watch("model.colors", function() {
                        savedService.update("colors", $scope.customization.$dirty);
                    }, true);

                    /**
                     * Blend the defaults and initial settings to get the current configuration.
                     *
                     * @param {Dictionary<string, string>} initial - initial colors from persistance layer.
                     * @param {Dictionary<string, string>} defaults - default colors for cPanel.
                     * @returns
                     */
                    function blendColors(initial, defaults) {
                        var copy = Object.assign({}, initial);
                        Object.keys(initial).forEach(function(key) {
                            if (copy[key] === "" || copy[key] === undefined || copy[key] === null) {

                                // Ignore empty keys so we keep the defaults.
                                delete copy[key];
                            }
                        });
                        var colors = Object.assign({}, defaults);
                        return Object.assign(colors, copy);
                    }

                    $scope.model.colors = blendColors( PAGE.data.jupiter.brand.colors, CONSTANTS.DEFAULT_COLORS );

                    /**
                     * Save the updates to the persistance layer.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.save = function($formCtrl) {
                        if (!$formCtrl.$valid) {
                            growl.error(LOCALE.maketext("The current customization is invalid."));
                            return;
                        }

                        growlMessages.destroyAllMessages();

                        if ($scope.saving || $scope.restoring) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;

                        /** @type {ColorBrandPartial} */
                        var partial = {
                            brand: { colors: $scope.model.colors },
                        };

                        customizeService.update(partial).then(function(update) {

                            // Update the local init values since we updated the server
                            PAGE.data.jupiter.brand.colors = angular.copy($scope.model.colors);
                            savedService.update("colors", false);
                            $formCtrl.$setPristine();

                            growl.success(LOCALE.maketext("The system successfully updated the brand colors."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update the brand colors."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Remove the brand colors from the customization.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.reset = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving || $scope.restoring) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.restoring = true;
                        return customizeService.delete("brand.colors")
                            .then(function(update) {
                                $scope.model.colors = blendColors( {}, CONSTANTS.DEFAULT_COLORS ); // Reset to defaults

                                // Update the local init values since we updated the server
                                PAGE.data.jupiter.brand.colors = angular.copy($scope.model.colors);

                                savedService.update("links", false);
                                $formCtrl.$setPristine();

                                growl.success(LOCALE.maketext("The system successfully restored the brand colors to the default."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to restore the brand colors to the default."));
                            })
                            .finally(function() {
                                $scope.restoring = false;
                            });
                    };
                },
            ]
        );

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/services/contactService.js
#                                                      Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* jshint -W089 */
/* jshint -W018 */

define(
    'app/services/contactService',[

        // Libraries
        "angular",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        "cjt/services/APICatcher",
    ],
    function(angular, API, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("customize.services.contactService", [
            "cjt2.services.apicatcher",
            "cjt2.services.api",
        ]);

        app.factory("contactService", ["APICatcher", function(APICatcher) {

            // return the factory interface
            return {

                /**
                 * Update the contact data for the company.
                 *
                 * @param {ContactInfo} contactInfo
                 * @returns
                 */
                setPublicContact: function(contactInfo) {
                    var apicall = new APIREQUEST.Class().initialize(
                        "", "set_public_contact", contactInfo
                    );

                    return APICatcher.promise(apicall);
                },
            };
        },
        ]);
    });

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/publicContactController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

( function() {
    "use strict";

    define(
        'app/views/publicContactController',[
            "lodash",
            "angular",
            "cjt/util/locale",
            "uiBootstrap",
            "app/services/contactService",
            "cjt/decorators/growlAPIReporter",
            "app/services/savedService",
        ],
        function(_, angular, LOCALE) {

            /**
             * @typedef ContactModel
             * @property {string} name - the name of the company
             * @property {string} url - the url to reach the company at.
             */

            // Create the module
            var app = angular.module(
                "customize.views.publicContactController", [
                    "customize.services.contactService",
                    "customize.services.savedService",
                ]
            );
            app.value("PAGE", PAGE);

            var PAGEDATA = PAGE.data;

            // It might be nice for the form model to be saved in this
            // scope; that way we could restore the form state between
            // loads of this view. AngularJS, though, doesn’t seem to like
            // to create FormController objects that are $dirty from the
            // get-go. We’d have to hook into some sort of post-render event,
            // and AngularJS *really* seems to want to stay away from that
            // kind of logic.
            //
            var SAVED_PCDATA = angular.copy( PAGEDATA.public_contact );

            // Setup the controller
            var controller = app.controller(
                "publicContactController",
                [
                    "$scope",
                    "contactService",
                    "savedService",
                    "growl",
                    "growlMessages",
                    function($scope, contactService, savedService, growl, growlMessages) {
                        angular.extend(
                            $scope,
                            {
                                has_root: !!PAGEDATA.has_root,
                                pcdata: angular.copy(SAVED_PCDATA),

                                /**
                                 * Save the public contacts.
                                 *
                                 * @param {*} form
                                 * @returns
                                 */
                                doSubmit: function doSubmit(form) {
                                    var scope = this;

                                    growlMessages.destroyAllMessages();

                                    return contactService.setPublicContact(this.pcdata).then( function() {
                                        angular.extend(SAVED_PCDATA, scope.pcdata);
                                        form.$setPristine();
                                        savedService.update("public-contact", false);
                                        growl.success(LOCALE.maketext("The public can now view the information that you provided in this form."));
                                    } );
                                },

                                /**
                                 * Reset the form to it intial state.
                                 */
                                resetForm: function resetForm(form) {
                                    growlMessages.destroyAllMessages();

                                    angular.extend(this.pcdata, SAVED_PCDATA);
                                    form.$setPristine();
                                },
                            }
                        );

                        // Watch for changes
                        $scope.$watchGroup([ "pcdata.name", "pcdata.url" ], function() {
                            if (!$scope.public_contact_form) {
                                return;
                            }
                            savedService.update("public-contact", $scope.public_contact_form.$dirty);
                        }, true);

                    },
                ]
            );

            return controller;
        }
    );

}());

/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

(function() {
    "use strict";

    define(
        'app/index',[
            "lodash",
            "angular",
            "cjt/core",
            "cjt/util/locale",
            "app/constants",
            "cjt/modules",
            "uiBootstrap",
            "cjt/directives/callout",
            "app/services/savedService",
            "app/services/beforeUnloadService",

            // Jupiter Views
            "app/views/jupiter/logoController",
            "app/views/jupiter/faviconController",
            "app/views/jupiter/linksController",
            "app/views/jupiter/colorsController",

            // Shared Views
            "app/views/publicContactController",
        ],
        function(_, angular, CJT, LOCALE, CONSTANTS) {
            return function() {
                angular.module("App", [
                    "cjt2.config.whm.configProvider", // This needs to load first
                    "ngRoute",
                    "ui.bootstrap",
                    "angular-growl",
                    "cjt2.whm",
                    "customize.services.savedService",
                    "customize.services.beforeUnloadService",

                    // Jupiter
                    "customize.views.logoController",
                    "customize.views.faviconController",
                    "customize.views.linksController",
                    "customize.views.colorsController",

                    // Shared
                    "customize.views.publicContactController",
                ]);

                var app = require(
                    [
                        "cjt/bootstrap",

                        // Application Modules
                        "uiBootstrap",

                        // Jupiter Views
                        "app/views/jupiter/logoController",
                        "app/views/jupiter/faviconController",
                        "app/views/jupiter/linksController",
                        "app/views/jupiter/colorsController",

                        // Shared Views
                        "app/views/publicContactController",

                        // Services
                        "app/services/contactService",
                        "app/services/customizeService",
                    ], function(BOOTSTRAP) {

                        var app = angular.module("App");
                        app.value("PAGE", PAGE);

                        app.value("firstLoad", {
                            branding: true,
                        });

                        app.controller("BaseController", [
                            "$rootScope",
                            "$scope",
                            "$route",
                            "$location",
                            "growl",
                            "growlMessages",
                            "$timeout",
                            "savedService",
                            "customizeService",
                            function($rootScope, $scope, $route, $location, growl, growlMessages, $timeout, savedService, customizeService) {
                                CONSTANTS.DEFAULT_THEME = PAGE.data.default_theme;
                                $scope.loading = false;
                                $scope.selectedThemeTabList = [];
                                savedService.registerTabs(CONSTANTS.JUPITER_TAB_ORDER);

                                // Convenience functions so we can track changing views for loading purposes
                                $rootScope.$on("$routeChangeStart", function() {
                                    if (savedService.needToSave()) {
                                        $scope.reportNotSaved();
                                        event.preventDefault();
                                    }

                                    $scope.loading = true;
                                });

                                $rootScope.$on("$routeChangeSuccess", function() {
                                    $scope.loading = false;
                                });

                                $rootScope.$on("$routeChangeError", function() {
                                    $scope.loading = false;
                                });

                                $rootScope.$on("onBeforeUnload", function(e, config) {
                                    if (savedService.needToSave()) {
                                        config.prompt = LOCALE.maketext("The current tab has unsaved changes. You should save the changes before you navigate to another tab.");
                                        e.preventDefault();

                                        return;
                                    }
                                    delete e["returnValue"];
                                });

                                /**
                                 * Select a tab by its key. See the indexes for each tab in the ./index.html.tt file.
                                 *
                                 * @param {number} index
                                 */
                                $scope.selectTab = function(index) {
                                    var tabInfo = getTabInfo();
                                    tabInfo.lastTab = index;
                                    var activeIndex = tabInfo.index[index];
                                    $scope.activeTab = activeIndex;
                                };

                                /**
                                 * Navigate to the selected path and change the tab being viewed.
                                 *
                                 * @param {string} path
                                 */
                                $scope.goTo = function(path) {
                                    var tabInfo = getTabInfo();
                                    tabInfo.lastTab = path;
                                    $scope.selectTab(path);
                                    $location.path(path);
                                    $scope.selectTab(path);
                                    $scope.currentTabName = path;
                                };

                                /**
                                 * Growl a message about not changing tabs.
                                 */
                                $scope.reportNotSaved = function() {
                                    growlMessages.destroyAllMessages();
                                    growl.error(LOCALE.maketext("The current tab has unsaved changes. You should save the changes before you navigate to another tab."));
                                };

                                /**
                                 * Do not let the user navigate away from a tab if there
                                 * is unsaved work.
                                 */
                                $scope.preventDeselect = function($event) {
                                    if (!$event || !$event.target) {
                                        return;
                                    }

                                    var tabName = findTabName(angular.element($event.target));
                                    if (savedService.needToSave($scope.currentTabName)) {
                                        if (tabName !== $scope.currentTabName) {
                                            $scope.reportNotSaved();
                                        }
                                        $event.preventDefault();
                                    }
                                    return;
                                };

                                /**
                                 * Dig thru the els to find the parent with the data-tab-name attribute
                                 *
                                 * @private
                                 * @param {JqLiteHtmlElement} el
                                 * @returns {string}
                                 */
                                function findTabName(el) {
                                    var name = el.attr("data-tab-name");
                                    if (name) {
                                        return name;
                                    }
                                    var parent = el.parent();
                                    if (parent) {
                                        return findTabName(parent);
                                    }
                                    return;
                                }

                                /**
                                 * @typedef ThemeInfo - a set of properties used to configure the tabs for a given theme.
                                 * @property {string[]} order - the list of tab names in the order they are shown.
                                 * @property {Dictionayr<string,number>} index - the lookup table of tab names to tab indexes.
                                 * @property {string} lastTab - the previously selected tab.
                                 */
                                /**
                                 * @typedef ThemesInfo - lookup table of tab configuration per theme.
                                 * @property {ThemeInfo} jupiter - the jupiter theme configuraiton
                                 */

                                /**
                                 * @name byTheme
                                 * @scope
                                 * @type {ThemesInfo}
                                 */
                                $scope.byTheme = {
                                    jupiter: {
                                        order: CONSTANTS.JUPITER_TAB_ORDER,
                                        index: CONSTANTS.JUPITER_TAB_INDEX,
                                        lastTab: "",
                                    },
                                };

                                $scope.selectedTheme = CONSTANTS.DEFAULT_THEME;

                                /**
                                 * Handle theme changes.
                                 */
                                $scope.onThemeSelect = function() {
                                    initTab();
                                };

                                /**
                                 * Retrieve the tab information for the current selected theme.
                                 *
                                 * @returns {ThemeInfo}
                                 */
                                function getTabInfo() {
                                    return $scope.byTheme[$scope.selectedTheme];
                                }

                                /**
                                 * Check if the theme matches the current theme.
                                 *
                                 * @param {string} themeName
                                 * @returns {boolean} true when they are the same, false otherwise.
                                 */
                                $scope.isTheme = function(themeName) {
                                    return $scope.selectedTheme === themeName;
                                };

                                /**
                                 * Check if the tab with the tabName is the active tab.
                                 *
                                 * @param {String} tabName
                                 * @returns {boolean} true when the tab is active, false otherwise.
                                 */
                                $scope.isActive = function(tabName) {
                                    return $scope.activeTab === tabName;
                                };

                                /**
                                 * Get the active tab name.
                                 *
                                 * @returns {string} The name of the active tab.
                                 */
                                $scope.getActiveTab = function() {
                                    return $scope.activeTab;
                                };

                                /**
                                 * The name of the currently selected tab
                                 * @type {string}
                                 */
                                $scope.currentTabName = "";

                                /**
                                 * Select the initial tab.
                                 */
                                function initTab() {
                                    var tabInfo = getTabInfo();
                                    $scope.selectedThemeTabList = customizeService.getThemeTabList(tabInfo);
                                    var tabName = tabInfo.lastTab || tabInfo.order[0];

                                    $timeout(function() {
                                        $scope.goTo(tabName);
                                    });
                                }

                                initTab();
                            },
                        ]);

                        app.config(["$routeProvider",
                            function($routeProvider) {

                                // Setup a route - copy this to add additional routes as necessary
                                $routeProvider.when("/logos", {
                                    controller: "logoController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/logo.ptt"),
                                });

                                $routeProvider.when("/colors", {
                                    controller: "colorsController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/colors.ptt"),
                                });

                                $routeProvider.when("/links", {
                                    controller: "linksController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/links.ptt"),
                                });

                                $routeProvider.when("/favicon", {
                                    controller: "faviconController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/jupiter/favicon.ptt"),
                                });

                                $routeProvider.when("/public-contact", {
                                    controller: "publicContactController",
                                    templateUrl: CJT.buildFullPath("cpanel_customization/views/publicContact.ptt"),
                                });

                                // default route
                                $routeProvider.otherwise({
                                    "redirectTo": "/" + CONSTANTS.DEFAULT_ROUTE,
                                });
                            },
                        ]);

                        // Initialize the application
                        BOOTSTRAP();

                    });

                return app;
            };
        }
    );

})();

