/*
# cpanel - whostmgr/docroot/templates/easyapache4/views/loadPackages.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/services/alertService",
    ],
    function(angular, _) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("loadPackages",
            ["$scope", "alertService", "wizardApi", "wizardState", "ea4Data", "ea4Util", "pkgResolution",
                function($scope, alertService, wizardApi, wizardState, ea4Data, ea4Util, pkgResolution) {
                    var loadPkgInfoData = function() {
                        var rawPkgList = ea4Data.getData("ea4RawPkgList");
                        if (rawPkgList === null) {
                            var promise = $scope.customize.loadPkgInfoList();

                            // REFACTOR: ERROR returns should be handled correctly.
                            promise.then(function() {
                                ea4Data.getEA4MetaInfo().then(function(response) {
                                    if (response.data) {
                                        ea4Util.additionalPkgList = response.data.additional_packages;

                                        // Find if additional packages don't exist in the system.
                                        var additionalPkgsExist = ea4Util.doAdditionalPkgsExist(ea4Util.additionalPkgList, $scope.customize.pkgInfoList);
                                        ea4Data.setData({ "additionalPkgsExist": additionalPkgsExist });
                                        var rebuildArgs = {
                                            rubyPkgsExist: ea4Util.doRubyPkgsExist($scope.customize.pkgInfoList),
                                            additionalPkgsExist: additionalPkgsExist,
                                        };
                                        wizardState.steps = wizardApi.rebuildWizardSteps(wizardState.steps, rebuildArgs);
                                        $scope.customize.proceed("mpm");
                                    }
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "alertMessages",
                                        closeable: false,
                                    });
                                });
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "alertMessages",
                                    closeable: false,
                                });
                            });
                        } else {
                            pkgResolution.resetCommonVariables();
                            $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");
                            $scope.customize.processPkgInfoList(rawPkgList);
                            wizardApi.init();
                            $scope.customize.proceed("mpm");
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        loadPkgInfoData();
                    });
                },
            ]
        );
    }
);
