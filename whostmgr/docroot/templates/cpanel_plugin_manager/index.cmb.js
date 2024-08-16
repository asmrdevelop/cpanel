/*
# cpanel_plugin_manager/services/createPluginService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W055 */

define(
    'app/services/createPluginService',[

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
         * Setup the configuration models API service
         */
        return app.factory("createPluginService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var createPluginService = function() {

            };

            createPluginService.prototype = {

                /**
                 * Generates the plugin file for the given input.
                 * @method generatePluginFile
                 * @param  {object} pluginData Has all the data necessary for plugin file creation.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                generatePluginFile: function(pluginData) {
                    if (pluginData !== undefined && pluginData.name !== "" ) {

                        var apiCall = new APIREQUEST.Class();
                        var deferred = $q.defer();

                        apiCall.initialize(NO_MODULE, "generate_cpanel_plugin");
                        apiCall.addArgument("plugin_name", pluginData.name);
                        apiCall.addArgument("install.json", pluginData.installListJson);
                        apiCall.addArgument("icons.json", pluginData.iconListJson);

                        API.promise(apiCall.getRunArguments()).
                            done(function(response) {
                                response = response.parsedResponse;
                                if (response.status) {
                                    deferred.resolve(response.data);
                                } else {
                                    deferred.reject(response.error);
                                }
                            });

                        return deferred.promise;
                    }
                }
            };

            return new createPluginService();
        }]);
    }
);

/*
* templates/cpanel_plugin_manager/views/createPluginController.js Copyright(c) 2020 cPanel, L.L.C.
*                                                                 All rights reserved.
* copyright@cpanel.net                                            http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/createPluginController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/createPluginService",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/validator/datatype-validators",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller(
            "createPluginController",
            ["$scope", "$anchorScroll", "alertService", "createPluginService", "PAGE",
                function($scope, $anchorScroll, alertService, createPluginService, PAGE) {

                    // Set default form variables for Add Item form. It is useful to clear the form when needed.
                    var defaultAddItemForm = {
                        itemData: {
                            id: "",
                            name: "",
                            description: "",
                            group_id: "",
                            order: "",
                            uri: "index.html",
                            overwrite: false,
                            featuremanager: false,
                            target: "",
                        },
                        showNewGroup: false,
                        newGroup: "",
                        itemIcon: "",
                    };

                    // Initialize createPlugin form
                    $scope.itemList = [];

                    $scope.item = angular.copy(defaultAddItemForm.itemData);

                    var groupList = [];

                    // Should contain the list of icons that get added to the plugin.
                    var iconList = {};

                    // Populate groups form the list obtained from backend.
                    $scope.groups = PAGE.groups;

                    // Get the list of item Ids to check against
                    var itemIds = PAGE.itemIds;

                    // Pre-populate the URI to index.html
                    $scope.item.uri = defaultAddItemForm.itemData.uri;

                    /**
                 * Add the newly entered item to new plugin to generate.
                 */
                    $scope.addItemToPlugin = function() {
                        if ($scope.addItemForm.$invalid) {
                            return;
                        }

                        if ($scope.item !== void 0) {

                            // Add Item type.
                            $scope.item.type = "link";

                            // Add Item group
                            if ($scope.newGroup !== void 0 && $scope.newGroup !== "") {

                                // Add the new group to the group list and assign this group to the current item
                                // to be added.
                                var newGroupId = $scope.newGroup.toLowerCase().split(" ").join("_");

                                var newGroupObj = { id: newGroupId, name: $scope.newGroup };

                                $scope.groups.push(newGroupObj);

                                // Assign this new group to the item.
                                $scope.item.group_id = newGroupId;

                                // Create an entry for the group list which gets added
                                // later into install.json.
                                var installGroupObj = {
                                    name: $scope.newGroup,
                                    type: "group",
                                    order: 99,   // Order is kept high for now. It will change when order input could be taken.
                                    id: newGroupId,
                                };

                                groupList.push(installGroupObj);
                            }

                            // We need to read the icon file before we say
                            // 'Add Item' is done. Since FileReader read is asynchronous,
                            // the process of pushing the item into itemList will be done in addIconItem
                            // function to make sure the icon file is read successfully before item is added.
                            readIconFile();
                        }
                    };

                    // This is custom validation function which validates
                    // if the entered item ID is already used in previously
                    // added items.
                    $scope.validateDuplicate = function() {

                        // Check for duplicate unique_id when something is
                        // entered in the id textbox.
                        if ($scope.item.id !== "") {
                            var isDuplicate = $scope.itemList.some(function(item) {
                                return item.id === $scope.item.id;
                            });

                            if (isDuplicate) {
                                $scope.addItemForm.txtItemId.$setValidity("unique", false);
                                $scope.focusOnId = true;
                                return isDuplicate;
                            } else {
                                $scope.addItemForm.txtItemId.$setValidity("unique", true);
                            }

                            // Check for existing cPanel items only if it is not previously
                            // checked.
                            var askOverwrite = itemIds.some(function(existingItem) {
                                return existingItem === $scope.item.id;
                            });

                            if (askOverwrite) {
                                $scope.addItemForm.txtItemId.$setValidity("existing", false);
                                $scope.showOverwrite = true;

                                return askOverwrite;
                            } else {
                                $scope.addItemForm.txtItemId.$setValidity("existing", true);
                                $scope.showOverwrite = false;
                                $scope.item.overwrite = false;

                                return askOverwrite;
                            }
                        }
                    };

                    // This is custom validation function which validates
                    // if the entered New Group Name is already used in previously
                    $scope.validateGroupNameDuplicate = function() {
                        var duplicate = false;

                        if ($scope.newGroup !== void 0 && $scope.newGroup !== "") {
                            var newGroupId = $scope.newGroup.toLowerCase().split(" ").join("_");
                            duplicate = $scope.groups.some(function(existingGroup) {
                                return existingGroup.id === newGroupId;
                            });
                        }

                        $scope.addItemForm.txtItemGroup.$setValidity("unique", !duplicate);
                    };

                    // This method updates the validation of item ID when
                    // user explicitly checks the checkbox to give his consent
                    // to overwrite an existing cPanel.
                    $scope.validateOverwrites = function() {
                        var pleaseOverwrite = $scope.item.overwrite;
                        $scope.addItemForm.txtItemId.$setValidity("existing", pleaseOverwrite);
                    };

                    $scope.clearItem = function() {
                        clearItemForm();
                    };

                    $scope.addGroup = function() {
                        $scope.showNewGroup = true;
                        if ($scope.item && $scope.item.group_id) {
                            $scope.item.group_id = "";
                        }
                        $scope.addItemForm.ddlGroup.$setPristine();
                    };

                    $scope.cancelNewGroup = function() {
                        $scope.showNewGroup = false;
                        $scope.newGroup = "";

                        // Reset the validation for the new group text field on cancelling.
                        $scope.addItemForm.txtItemGroup.$setValidity("unique", true);
                        $scope.addItemForm.txtItemGroup.$setPristine();
                    };

                    $scope.removeItem = function(itemId) {
                        if (itemId !== "") {
                            var itemList = $scope.itemList;

                            var removeItem =  itemList.filter(function(item) {
                                return item.id === itemId;
                            });

                            if (removeItem && removeItem.length === 1) {
                                var index = itemList.indexOf(removeItem[0]);
                                if (index !== -1) {
                                    $scope.itemList.splice(index, 1);
                                }

                                var removeIcon = removeItem[0].icon;

                                // Also remove the icon entry from iconlist.
                                delete iconList[removeIcon];
                            }

                        }
                    };

                    $scope.generatePlugin = function() {

                        if ($scope.createPluginForm.$invalid) {
                            return;
                        }

                        groupList = groupList.filter(function(group) {
                            return $scope.itemList.some(function(item) {
                                return item.group_id === group.id;
                            });
                        });

                        // Convert iconList object to JSON string.
                        var iconListJson = angular.toJson(iconList);

                        // Merge itemlist and group list
                        var installList = groupList.concat($scope.itemList);

                        // Convert installList object to JSON string.
                        var installListJson = angular.toJson(installList);

                        var pluginData = {
                            "name": $scope.pluginName,
                            "installListJson": installListJson,
                            "iconListJson": iconListJson,
                        };

                        return createPluginService.generatePluginFile(pluginData)
                            .then(
                                function(data) {
                                    if (data.tarball !== void 0) {
                                        $scope.notice = true;
                                        var downloadUrl = "download/" + data.tarball;
                                        alertService.add({
                                            type: "success",
                                            message: LOCALE.maketext("The plugin file “[_1]” was generated successfully. Please [output,url,_2,download the plugin,target,blank,title,_1] before creating a new one.", data.tarball, downloadUrl),
                                            id: "alertAddSuccess",
                                            closeable: false,
                                        });
                                        clearItemForm();
                                        clearCreatePluginForm();
                                    }
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "alertMessages",
                                        closeable: false,
                                    });
                                }
                            );
                    };

                    function clearItemForm() {
                        if ($scope.addItemForm.$dirty) {
                            $scope.addItemForm.$setPristine();
                            $scope.item = angular.copy(defaultAddItemForm.itemData);
                            $scope.showNewGroup = defaultAddItemForm.showNewGroup;
                            $scope.newGroup = defaultAddItemForm.newGroup;
                            $scope.itemIcon = defaultAddItemForm.itemIcon;
                            $scope.showOverwrite = false;
                            $scope.focusOnId = true;

                            // Browsers like Chrome do not fire 'changed' event on the file field
                            // if we try to select the same file again. But we need it to fire the event
                            // in our case, as we are handling the 'add item' just through javascript and
                            // multiple items may want to have same icon file uploaded.
                            var fileField = document.getElementById("fileIcon");
                            if (fileField !== void 0) {
                                fileField.value = defaultAddItemForm.itemIcon;
                            }
                        }
                    }

                    function clearCreatePluginForm() {
                        if ($scope.createPluginForm.$dirty) {
                            $scope.createPluginForm.$setPristine();
                            $scope.itemList = [];
                            $scope.pluginName = "";
                            iconList = {};
                        }
                    }

                    function readIconFile() {
                        var reader = new FileReader();

                        reader.onloadend = function() {
                            $scope.addItemProcessing = false;
                            $scope.$apply(addIconToItem(reader.result));
                        };

                        if ($scope.itemIcon) {
                            $scope.addItemProcessing = true;
                            reader.readAsDataURL($scope.itemIcon);
                        }
                    }

                    function addIconToItem(iconFileData) {

                        // Icons in the cPanel theme are always named by the item's id.
                        // AND it should be a .png or .svg file.

                        var imgName = $scope.itemIcon.name;
                        var iconExtension = imgName.substr(imgName.lastIndexOf("."));

                        var iconFileName = $scope.item.icon = $scope.item.id + iconExtension;
                        iconList[iconFileName] = iconFileData;

                        $scope.itemList.push($scope.item);

                        // Add the new item's id to the itemIds list to ensure duplicate id validation
                        // happens correctly.
                        // itemIds.push($scope.item.id);

                        clearItemForm();
                    }
                },
            ]);
    }
);

/* global define */
define('app/directives/fileModel',[
    "angular"
], function(angular) {

    // This directive updates the $scope when an <input type="file"> changes.
    // AngularJS ng-model does not keep the state of <input type="file"> linked with $scope.
    angular.module("App")
        .directive("fileModel", ["$parse", function($parse) {
            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    var model = $parse($attrs.fileModel);
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {
                            $scope.$apply(function() {
                                model.assign($scope, file);

                                // Mark as dirty
                                $ngModelCtrl.$setViewValue($ngModelCtrl.$modelValue);
                            });
                        }
                    });
                }
            };
        }]);
});

/* global define */
define('app/directives/fileType',[
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileType", [function() {
            function checkType(file, types) {
                var valid = false;
                angular.forEach(types, function(type) {
                    valid = valid || file.type === type;
                });
                return valid;
            }
            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {

                        // Check for empty files being uploaded
                            if (file.size === 0) {
                                $ngModelCtrl.$setValidity("filesize", false);
                            } else {
                                $ngModelCtrl.$setValidity("filesize", true);
                            }

                            if (!checkType(file, $scope.$eval($attrs.fileType))) {
                                $ngModelCtrl.$setValidity("filetype", false);
                            } else {
                                $ngModelCtrl.$setValidity("filetype", true);
                            }
                        }
                    });
                }
            };
        }]);
});

/*
# templates/cpanel_plugin_manager/index.js                 Copyright 2022 cPanel, L.L.C.
#                                                          All rights reserved.
# copyright@cpanel.net                                     http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute"
    ],
    function(angular, $, _, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/views/applicationController",
                    "app/views/createPluginController",
                    "app/directives/fileModel",
                    "app/directives/fileType",
                    "cjt/directives/autoFocus",
                    "cjt/services/autoTopService",
                    "cjt/directives/actionButtonDirective"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        pluginList: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/createPlugin", {
                                controller: "createPluginController",
                                templateUrl: CJT.buildFullPath("cpanel_plugin_manager/views/createPluginView.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: "/createPlugin"
                            });
                        }
                    ]);

                    app.run(["autoTopService", function(autoTopService) {

                        // Setup the automatic scroll to top for view changes
                        autoTopService.initialize();
                    }]);

                    // Initialize the application
                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

