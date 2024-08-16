/*
# cpanel - whostmgr/docroot/templates/easyapache4/views/customize.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/ea4Data",
        "app/services/pkgResolution",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("customize",
            [ "$scope", "ea4Data", "pkgResolution", "wizardState", "wizardApi", "$location", "ea4Util",
                function($scope, ea4Data, pkgResolution, wizardState, wizardApi, $location, ea4Util) {
                    $scope.customize = {
                        pkgInfoList: {},
                        selectedPkgs: [],

                        // This contains only the current step's package info.
                        currentPkgInfoList: {},
                        saveProfilePopup: {
                            position: "top",
                            showTop: false,
                            showBottom: false,
                        },

                        // this contains the packages to run the update
                        activeProfilePkgs: [],
                    };

                    $scope.customize.wizard = wizardState;
                    $scope.customize.wizardApi = wizardApi;

                    /* -------  Save As Profile ------- */
                    $scope.customize.showsaveProfilePopup = function(position) {
                        $scope.customize.saveProfilePopup.position = position;
                        if (position !== "top") {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = true;
                        } else {
                            $scope.customize.saveProfilePopup.showTop = true;
                            $scope.customize.saveProfilePopup.showBottom = false;
                        }
                    };

                    $scope.customize.clearSaveProfilePopup = function(position) {
                        if (position !== "top") {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = false;
                            $scope.customize.saveProfilePopup.position = "top";
                        } else {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = false;
                        }
                    };

                    $scope.customize.loadData = function(type) {
                        pkgResolution.resetCommonVariables();
                        $scope.customize.pkgInfoList = ea4Data.getData("pkgInfoList");
                        var customizeMode = ea4Data.getData("customize");
                        if (_.keys($scope.customize.pkgInfoList).length <= 0) {
                            ea4Data.cancelOperation();
                        } else {
                            $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");

                            // set showWizard flag
                            wizardApi.updateWizard(
                                {
                                    "showWizard": customizeMode,
                                    "currentStep": type,
                                }
                            );

                            if (type === "review") {
                                ea4Util.hideFooter();
                            } else {
                                ea4Util.showFooter();
                            }
                        }
                    };

                    $scope.customize.processPkgInfoList = function(data) {
                        if (typeof data !== "undefined") {
                            var recos = ea4Data.getData("ea4Recommendations");
                            $scope.customize.pkgInfoList = ea4Data.buildPkgInfoList($scope.customize.selectedPkgs, data, recos);
                            ea4Data.setData({ "pkgInfoList": $scope.customize.pkgInfoList });
                        }
                    };

                    $scope.customize.loadPkgInfoList = function() {
                        pkgResolution.resetCommonVariables();
                        $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");

                        var promise = ea4Data.getPkgInfoList();
                        promise.then(function(data) {
                            $scope.customize.processPkgInfoList(data);
                        });
                        return promise;
                    };

                    $scope.customize.proceed = function(step) {
                        ea4Data.setData(
                            {
                                "pkgInfoList": $scope.customize.pkgInfoList,
                                "selectedPkgs": $scope.customize.selectedPkgs,
                            }
                        );
                        wizardApi.next(step);
                    };

                    $scope.customize.getStepClass = function(step) {
                        if (step === $scope.customize.wizard.currentStep) {
                            return "active";
                        }
                    };

                    $scope.customize.getViewWidthCss = function(isWizard) {
                        return (isWizard ? "col-xs-9" : "col-xs-12");
                    };

                    $scope.customize.provisionEA4Updates = function() {

                        // This cancels any previously customized packages.
                        ea4Data.clearEA4LocalStorageItems();
                        ea4Data.setData(
                            {
                                "selectedPkgs": $scope.customize.activeProfilePkgs,
                                "ea4Update": true,
                            });
                        $location.path("review");
                    };

                    $scope.customize.toggleUpdateButton = function() {
                        var updateCount = $scope.customize.checkUpdateInfo.pkgNumber;

                        if (updateCount > 0) {
                            $scope.customize.checkUpdateInfo.btnText = LOCALE.maketext("Update [asis,EasyApache 4]");
                            $scope.customize.checkUpdateInfo.btnTitle = LOCALE.maketext("Update [asis,EasyApache 4]");
                            $scope.customize.checkUpdateInfo.btnCss = "btn-primary";
                        } else {
                            $scope.customize.checkUpdateInfo.btnText = LOCALE.maketext("[asis,EasyApache 4] is up to date[comment,no punctuation due to usage]");
                            $scope.customize.checkUpdateInfo.btnTitle = LOCALE.maketext("[asis,EasyApache 4] is up to date[comment,no punctuation due to usage]");
                            $scope.customize.checkUpdateInfo.btnCss = "btn-primary disabled";
                        }
                    };
                },
            ]
        );
    }
);
