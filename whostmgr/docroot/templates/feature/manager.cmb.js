/*
# templates/feature/views/commonController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

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
# feature/services/featureListService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/services/featureListService',[

        // Libraries
        "angular",
        "lodash",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, _, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * Setup the feature list models API service
         */
        app.factory("featureListService", ["$q", "APIService", "PAGE", function($q, APIService, PAGE) {

            /**
             * Converts the response to our application data structure
             *
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
                        items.push(data[i]);
                    }

                    var meta = response.meta;

                    var totalItems = meta.paginate.total_records || data.length;
                    var totalPages = meta.paginate.total_pages || 1;

                    return {
                        items: items,
                        totalItems: totalItems,
                        totalPages: totalPages,
                        status: response.status
                    };
                } else {
                    return {
                        items: [],
                        totalItems: 0,
                        totalPages: 0,
                        status: response.status
                    };
                }
            }

            /**
             * Helper method to retrieve feature lists in chained actions
             *
             * @method _fetchLists
             * @private
             * @param  {Deferred} deferred
             * @return {Promise}
             */
            function _fetchLists(deferred) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "get_featurelists");
                apiCall.addSorting("", "asc", "lexicographic_caseless");

                this.deferred(apiCall, {
                    transformAPISuccess: convertResponseToList
                }, deferred);

                // pass the promise back to the controller
                return deferred.promise;
            }

            /**
             * Helper method to save addon feature lists in chained actions
             *
             * @method _saveAddons
             * @private
             * @param  {Deferred} deferred
             * @param  {String} name The name of the base featurelist calling this chained action
             * @param  {Array} list The Array of addons features to be saved
             * @return {Promise}
             */
            function _saveAddons(deferred, name, list) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(NO_MODULE, "update_featurelist");
                apiCall.addArgument("featurelist", name + ".cpaddons");

                _.each(list, function(feature) {
                    apiCall.addArgument(feature.name, feature.value);
                });

                this.deferred(apiCall, {}, deferred);

                // pass the promise back to the controller
                return deferred.promise;
            }

            // Set up the service's constructor and parent
            var FeatureListService = function() {};
            FeatureListService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(FeatureListService.prototype, {

                /**
                 * Get a list of feature lists
                 *
                 * @method loadFeatureLists
                 * @return {Promise} Promise that will fulfill the request.
                 * @throws Error
                 */
                loadFeatureLists: function() {
                    var deferred = $q.defer();

                    // pass the promise back to the controller
                    return _fetchLists.call(this, deferred);
                },

                /**
                 * Get a single feature list by its name from the backend and merges
                 * it with the list of descriptions
                 *
                 * @method load
                 * @param {String} name The name of a feature list to fetch.
                 * @param {Array} dictionary Array of human readable labels for feature names.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                load: function(name, dictionary) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "get_featurelist_data");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        apiSuccess: function(response, deferred) {
                            response.items = [];

                            // legacy features only supported by x and x2 interfaces
                            var legacyNames = ["bbs", "chat", "cpanelpro_support", "searchsubmit", "advguest", "guest", "cgi", "scgiwrap", "counter", "entropybanner", "entropysearch", "clock", "countdown", "randhtml", "videotut", "getstart"],
                                featurePluginFlag = false,
                                featureAddonFlag = false,
                                legacyFeature,
                                featureLabel,
                                featureID,
                                featureState;

                            _.each(response.data.features, function(feature) {

                                legacyFeature = false;
                                if ( _.includes(legacyNames, feature.id) ) {
                                    if ( PAGE.legacySupport ) {
                                        legacyFeature = true;
                                    } else {

                                        // exclude legacy feature
                                        return;
                                    }
                                }

                                if ( feature.id === "fantastico" && !PAGE.fantasticoSupport ) {

                                    // exclude fantastico feature
                                    return;
                                }

                                // check the dictionary for additional meta data about the feature
                                featureID = feature.id;
                                featureLabel = feature.id;
                                if ( feature.id in dictionary ) {
                                    featureLabel = dictionary[feature.id].name;
                                    featurePluginFlag = dictionary[feature.id].is_plugin === "1" ? true : false;
                                    featureAddonFlag = dictionary[feature.id].is_cpaddon === "1" ? true : false;
                                }

                                // handle api oddities for disabled list
                                featureState = false;
                                if ( name === "disabled" ) {
                                    if ( feature.value === "0" ) {
                                        featureState = true;
                                    }
                                } else {
                                    featureState = feature.value === "1" ? true : false;
                                }

                                response.items.push({
                                    name: featureID,
                                    label: featureLabel,
                                    value: featureState,
                                    legacy: legacyFeature,
                                    disabled: feature.is_disabled === "1" ? true : false,
                                    plugin: featurePluginFlag,
                                    addon: featureAddonFlag
                                });
                            }, response.data.features);

                            // sort features by the readable labels
                            response.items = _.sortBy(response.items, function(feature) {
                                return feature.label.toLowerCase();
                            });

                            deferred.resolve(response);
                        }
                    });

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Saves the states of a list of a features
                 *
                 * @method save
                 * @param {String} name The name of a feature list to save.
                 * @param {Array} list The array of list objects to save.

                 * @return {Promise} Promise that will fulfill the request.
                 */
                save: function(name, list) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "update_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var addons = [], featureList = angular.copy(list);
                    _.each(featureList, function(feature) {

                        // conditionally flip the logic from the checkboxes
                        if ( name === "disabled" ) {
                            feature.value = feature.value === true ? "0" : "1";
                        } else {
                            feature.value = feature.value === true ? "1" : "0";
                        }

                        if ( feature.addon ) {
                            addons.push(feature);
                        } else {
                            apiCall.addArgument(feature.name, feature.value);
                        }
                    });

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function() {
                            _saveAddons.call(this, deferred, name, addons);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Add a feature list
                 *
                 * @method add
                 * @param {String} name The name of the feature list to be created
                 * @return {Promise} Promise that will fulfill the request.
                 */
                add: function(name) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "create_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function(response) {
                            deferred.resolve(response);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                 * Delete a feature list by its name
                 *
                 * @method remove
                 * @param  {String} name The name of the feature list to delete.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                remove: function(name) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "delete_featurelist");
                    apiCall.addArgument("featurelist", name);

                    var deferred = this.deferred(apiCall, {
                        context: this,
                        apiSuccess: function() {
                            deferred.notify();
                            _fetchLists.call(this, deferred);
                        }
                    }, deferred);

                    // pass the promise back to the controller
                    return deferred.promise;
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                *
                * @method  prepareList
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return convertResponseToList(response);
                }
            });

            return new FeatureListService();
        }]);
    }
);

/*
# feature/views/featureListController.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/featureListController',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/filters/splitFilter",
        "cjt/filters/htmlFilter",
        "cjt/directives/spinnerDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/services/alertService",
        "app/services/featureListService",
        "cjt/io/whm-v1-querystring-service"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "featureListController", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$timeout",
                "featureListService",
                "alertService",
                "PAGE",
                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $timeout,
                    featureListService,
                    alertService,
                    PAGE) {

                    $scope.loadingPageData = true;
                    $scope.loadingView = false;
                    $scope.onlyReseller = !PAGE.hasRoot;

                    /**
                         * Returns true if the feature list can be edited
                         *
                         * @method isEditable
                         * @param  {String} list The name of the feature list to check
                         * @return {Boolean}
                         */
                    $scope.isEditable = function(list) {
                        return typeof list !== "undefined" && list !== "";
                    };

                    /**
                         * Returns true if the feature list can be deleted
                         *
                         * @method isDeletable
                         * @param  {String} list The name of the feature list to check
                         * @return {Boolean}
                         */
                    $scope.isDeletable = function(list) {
                        if ( typeof list !== "undefined" ) {
                            return $scope.isEditable(list) && !$scope.isSystemList(list);
                        }
                        return false;
                    };

                    /**
                         * Returns true if the feature list is reserved for use by the system
                         *
                         * @method isSystemList
                         * @param  {String} list The name of the feature list to check
                         * @return {Boolean}
                         */
                    $scope.isSystemList = function(list) {
                        if ( typeof list !== "undefined" ) {
                            return list === "default" || list === "disabled" || list === "Mail Only";
                        }
                        return false;
                    };

                    /**
                         * Add a feature list
                         *
                         * @method add
                         * @param  {String} list The name of the feature list to add
                         * @return {Promise}
                         */
                    $scope.add = function(list) {
                        if ( !$scope.formAddFeature.$valid ) {

                            // dirty the name field and bail out
                            var currentValue = $scope.formAddFeature.txtNewFeatureList.$viewValue;
                            $scope.formAddFeature.txtNewFeatureList.$setViewValue(currentValue);
                            return;
                        }

                        // reseller check

                        if ( !PAGE.hasRoot ) {
                            var re = new RegExp( "^" + PAGE.remoteUser + "_\\w+", "i" );
                            if ( list.search( re ) === -1 ) {
                                list = PAGE.remoteUser + "_" + list;
                            }
                        }

                        return featureListService
                            .add(list)
                            .then(function() {

                                // success
                                $scope.loadingView = true;
                                $scope.loadView("editFeatureList", { name: list });
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorAddingingFeatureList"
                                });
                            });
                    };

                    /**
                         * Deletes a feature list
                         *
                         * @method delete
                         * @param  {String} list The name of the feature list to delete
                         * @return {Promise}
                         */
                    $scope.delete = function(list) {

                        return featureListService
                            .remove(list)
                            .then(function(results) {

                                // success
                                $scope.featureLists = results.items;
                                $scope.selectedFeatureList = $scope.featureLists[0];
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorDeletingFeatureList"
                                });
                            }, function() {

                                // notification
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully deleted the “[_1]” feature list.", _.escape(list)),
                                    id: "alertDeleteSuccess"
                                });
                            });
                    };

                    /**
                         * Fetch the feature lists
                         * @method fetch
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.fetch = function() {
                        $scope.loadingPageData = true;
                        alertService.removeById("errorFetchFeatureLists");

                        return featureListService
                            .loadFeatureLists()
                            .then(function(results) {
                                $scope.featureLists = results.items;
                                $scope.selectedFeatureList = $scope.featureLists[0];
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetchFeatureLists"
                                });

                                // throw an error for chained promises
                                throw error;
                            }).finally(function() {
                                $scope.loadingPageData = false;
                            });

                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // check for page data in the template if this is a first load
                        if (app.firstLoad.featureList && PAGE.featureLists) {
                            app.firstLoad.featureList = false;
                            $scope.loadingPageData = false;

                            var featureLists = featureListService.prepareList(PAGE.featureLists);
                            $scope.featureLists = featureLists.items;
                            $scope.selectedFeatureList = $scope.featureLists[0];
                            if ( !featureLists.status ) {
                                $scope.loadingPageData = "error";
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("There was a problem loading the page. The system is reporting the following error: [_1].", PAGE.featureLists.metadata.reason),
                                    id: "errorFetchFeatureLists"
                                });
                            }
                        } else {

                            // reload the feature lists
                            $scope.fetch();
                        }
                    });
                }
            ]);

        return controller;
    }
);

/*
# templates/feature/views/editFeatureListController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* exported $sce */

define(
    'app/views/editFeatureListController',[
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/searchDirective",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/featureListService"
    ],
    function(angular, _, $, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "editFeatureListController",
            ["$scope", "$location", "$anchorScroll", "$routeParams", "spinnerAPI", "alertService", "featureListService", "$sce", "PAGE",
                function($scope, $location, $anchorScroll, $routeParams, spinnerAPI, alertService, featureListService, $sce, PAGE) {

                    $scope.featureListName = $routeParams.name;
                    $scope.featureListHeading = LOCALE.maketext("Select all features for: [_1]", $scope.featureListName);

                    /**
                 * Toggles the checked states of each item in the feature list
                 *
                 * @method toggleAllFeatures
                 */
                    $scope.toggleAllFeatures = function() {

                    // the next state should be the opposite of the current
                        var nextState = $scope.allFeaturesChecked() ? false : true;

                        _.each($scope.featureList, function(feature) {
                            if ( !feature.disabled ) {
                                feature.value = nextState;
                            }
                        });
                    };

                    /**
                 * Helper function that returns 1 if all features are checked, 0 otherwise
                 *
                 * @method allFeaturesChecked
                 * @return {Boolean}
                 */
                    $scope.allFeaturesChecked = function() {

                    // bail out if the page is still loading or feature list is
                    // nonexistent
                        if ($scope.loadingPageData || !$scope.featureList) {
                            return false;
                        }

                        var currentFeature;
                        for ( var i = 0, length = $scope.featureList.length; i < length; i++ ) {
                            currentFeature = $scope.featureList[i];
                            if ( currentFeature.value === false && !currentFeature.disabled ) {
                                return false;
                            }
                        }

                        // all list items were checked
                        return true;
                    };

                    /**
                 * Save the list of features and return to the feature list view
                 *
                 * @method save
                 * @param  {Array} list Array of feature objects.
                 * @return {Promise}
                 */
                    $scope.save = function(list) {
                        return featureListService
                            .save($scope.featureListName, list)
                            .then(function success() {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully updated the “[_1]” feature list.", _.escape($scope.featureListName)),
                                    id: "alertSaveSuccess",
                                    replace: true
                                });
                                $scope.loadView("featureList");
                            }, function failure(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorSaveFeatureList"
                                });
                            }
                            );
                    };

                    /**
                 * Fetch the list of hits from the server
                 * @method fetch
                 * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                 */
                    $scope.fetch = function() {
                        $scope.loadingPageData = true;
                        spinnerAPI.start("featureListSpinner");
                        alertService.removeById("errorFetchFeatureList");

                        return featureListService
                            .load($scope.featureListName, $scope.featureDescriptions)
                            .then(function success(results) {
                                $scope.featureList = results.items;
                                $scope.loadingPageData = false;
                            }, function failure(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "errorFetchFeatureList"
                                });

                                // throw an error for chained promises
                                throw error;
                            }).finally(function() {
                                $scope.loadingPageData = false;
                                spinnerAPI.stop("featureListSpinner");
                            });

                    };

                    $scope.$on("$viewContentLoaded", function() {
                        alertService.clear();
                        var featureDescriptions = featureListService.prepareList(PAGE.featureDescriptions);
                        $scope.featureDescriptions = _.fromPairs(_.zip(_.map(featureDescriptions.items, "id"), featureDescriptions.items));
                        if ( !featureDescriptions.status ) {
                            $scope.loadingPageData = "error";
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("There was a problem loading the page. The system is reporting the following error: [_1].", PAGE.featureDescriptions.metadata.reason),
                                id: "errorFetchFeatureDescriptions"
                            });
                        } else {

                        // load the feature list
                            $scope.fetch();
                        }
                    });
                }
            ]);

        return controller;
    }
);

/*
# templates/feature/manager.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/manager',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        return function() {

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
                    "cjt/filters/breakFilter",
                    "app/views/commonController",
                    "app/views/featureListController",
                    "app/views/editFeatureListController",
                    "cjt/services/whm/breadcrumbService"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        featureList: true
                    };

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/featureList", {
                                controller: "featureListController",
                                templateUrl: CJT.buildFullPath("feature/views/featureListView.ptt"),
                                breadcrumb: LOCALE.maketext("Feature Lists"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editFeatureList", {
                                controller: "editFeatureListController",
                                templateUrl: CJT.buildFullPath("feature/views/editFeatureListView.ptt"),
                                breadcrumb: LOCALE.maketext("Edit Feature List"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                redirectTo: function(routeParams, path, search) {
                                    return "/featureList?" + window.location.search;
                                }
                            });
                        }
                    ]);

                    app.run(["breadcrumbService", function(breadcrumbService) {

                        // Setup the breadcrumbs service
                        breadcrumbService.initialize();
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

