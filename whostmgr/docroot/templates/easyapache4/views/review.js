/*
# templates/easyapache4/views/review.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "app/services/ea4Data",
        "app/services/ea4Util"
    ],
    function(angular, _) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("review",
            [ "$scope", "$location", "ea4Data", "ea4Util", "growlMessages",
                function($scope, $location, ea4Data, ea4Util, growlMessages) {
                    $scope.readyToProvision = false;
                    $scope.gettingResults = true;

                    /**
                    * We can send packages from external apps directly to this view.
                    * The data should be sent as querystring params.
                    * 'queryStr' variable will track those params.
                    *
                    * querystring param: 'install': to install a package (can be multiple).
                    * querystring param: 'uninstall': to uninstall a package (can be multiple).
                    * Example:
                    * <url>/<cpsesskey>/scripts7/EasyApache4/review?install=mpm-prefork&install=cgi&uninstall=mpm-worker&uninstall=cgid
                    */
                    var queryStr = {};

                    /**
                    * Prepares the selected packages to be installed and does an
                    * API call to resolve those packages.
                    *
                    * @method prepareForReview
                    * @param {Array} A list of packages to be installed.
                    * @param {String} [Optional] profile id(usually path of a profile).
                    */
                    var prepareForReview = function(packageListForReview, profileId) {

                        // Get status of each package in the package list
                        ea4Data.resolvePackages(packageListForReview).then(function(data) {

                            // Get the packages display format
                            $scope.installList = ea4Util.getFormattedPackageList(data.install);
                            $scope.uninstallList = ea4Util.getFormattedPackageList(data.uninstall);
                            $scope.upgradeList = ea4Util.getFormattedPackageList(data.upgrade);
                            $scope.existingList = ea4Util.getFormattedPackageList(data.unaffected);

                            if (!$scope.installList.length && !$scope.upgradeList.length && !$scope.uninstallList.length) {
                                $scope.noActionRequired = true;
                                return;
                            }

                            // Put all lists into Web Storage
                            ea4Data.setData(
                                {
                                    "provisionActions":
                                    {
                                        profileId: profileId,
                                        install: data.install,
                                        uninstall: data.uninstall,
                                        upgrade: data.upgrade
                                    }
                                });

                            // Enable the Provision button
                            $scope.readyToProvision = true;

                            // Allow provision to run
                            ea4Data.provisionReady(true);
                        }, function(error) {
                            $scope.apiError = true;
                            $scope.yumErrorMessage = error;
                        }).finally(function() {
                            $scope.gettingResults = false;
                        });
                    };

                    /**
                    * update selectedPackages with new install and/or uninstall
                    * packages sent through querystring from directly called from
                    * an external application.
                    * This helps in by-passing customize steps when we need to install
                    * few packages required in other applications.
                    *
                    * @method updateSelPackagesAndReview
                    * @param {Object} angular query string object
                    */
                    var updateSelPackagesAndReview = function(qs) {

                        // 1. Get the current package list.
                        // 2. Add packages that need to be installed to 'selPkgs'
                        // 3. Remove packages that need to be uninstalled from 'selPkgs'.
                        var selPkgs = [];
                        ea4Data.ea4GetCurrentPkgList().then(function(result) {
                            if (result.status) {
                                selPkgs = result.data;

                                // qs["install"] may have a single string or an array of strings.
                                var installList = (_.isArray(qs["install"])) ? qs["install"] : [ qs["install"] ];
                                selPkgs = _.union(selPkgs, installList);

                                // qs["uninstall"] may have a single string or an array of strings.
                                var uninstallList = (_.isArray(qs["uninstall"])) ? qs["uninstall"] : [ qs["uninstall"] ];
                                selPkgs = _.difference(selPkgs, uninstallList);
                                prepareForReview(selPkgs);
                            }
                        });
                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // A list of install/uninstall package set sent through querystring from an external location.
                        queryStr = $location.search();
                        if (!_.isEmpty(queryStr) &&
                        (!_.isEmpty(queryStr["install"]) || !_.isEmpty(queryStr["uninstall"]))) {
                            updateSelPackagesAndReview(queryStr);
                        } else {
                            var customize = ea4Data.getData("customize");
                            var ea4Update = ea4Data.getData("ea4Update");
                            if (customize) {
                                $scope.customize.loadData("review");
                                prepareForReview(ea4Data.getData("selectedPkgs"));
                            } else if (ea4Update) {
                                prepareForReview(ea4Data.getData("selectedPkgs"));
                            } else {
                                var selectedProfile = ea4Data.getData("selectedProfile");
                                if (!selectedProfile) {
                                    ea4Data.cancelOperation();
                                }
                                prepareForReview(selectedProfile.pkgs, selectedProfile.fullPath);
                            }
                        }
                    });

                    $scope.cancel = function() {
                        ea4Data.cancelOperation();
                    };
                }]);
    }
);
