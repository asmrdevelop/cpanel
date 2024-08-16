/*
# templates/backup_migration/views/main.js           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "app/services/backupMigrationAPI",
        "cjt/directives/actionButtonDirective"
    ],
    function(angular, $, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("whm.backupMigration");

        app.controller("ModalInstanceCtrl", ["$scope", "$uibModalInstance",
            function($scope, $uibModalInstance) {
                $scope.closeModal = function() {
                    $uibModalInstance.close();
                };

                $scope.runIt = function() {
                    $uibModalInstance.close(true);
                };
            }
        ]);

        app.controller("main", ["$scope", "$rootScope", "$location", "$anchorScroll", "$routeParams", "$q", "spinnerAPI", "backupMigrationAPI", "$uibModal", "$interval", "$sce", "$window",
            function($scope, $rootScope, $location, $anchorScroll, $routeParams, $q, spinnerAPI, backupMigrationAPI, $uibModal, $interval, $sce, $window) {

                $scope.migrate = function() {
                    var $modalInstance = $uibModal.open({
                        templateUrl: "migrationModalContent.tmpl",
                        controller: "ModalInstanceCtrl"
                    });

                    $modalInstance.result.then(function(proceed) {
                        if (proceed) {
                            $scope.runMigration();
                        }
                    });
                };

                $scope.runMigration = function() {
                    spinnerAPI.start("runningSpinner");
                    $scope.running = true;
                    backupMigrationAPI.run_migration($scope.keepConfig).then(function(result) {
                        $scope.running = false;
                        $scope.finished = true;
                        if (!result.result) {
                            $scope.errorDetected = true;
                            $scope.errorMessage = result.reason;
                        }
                    });
                };

                $scope.reload = function() {
                    $window.location.reload();
                };

                $scope.init = function() {
                    $scope.allowKeepConfig = PAGE.backup_status;
                };

                $scope.init();
            }
        ]);
    }
);
