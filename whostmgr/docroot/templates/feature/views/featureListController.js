/*
# feature/views/featureListController.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
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
