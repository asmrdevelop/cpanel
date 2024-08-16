/*
# templates/feature/views/editFeatureListController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* exported $sce */

define(
    [
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
