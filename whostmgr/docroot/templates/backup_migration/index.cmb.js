/*
# templates/backup_migration/services/backupMigrationAPI.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/backupMigrationAPI',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1"
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER) {

        // Retrieve the current application
        var app = angular.module("whm.backupMigration");

        var backupMigrationAPI = app.factory("backupMigrationAPI", ["$q", function($q) {

            var backupMigrationAPI = {};

            backupMigrationAPI.run_migration = function(keepConfig) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "convert_and_migrate_from_legacy_config");

                if (keepConfig) {
                    apiCall.addArgument("no_convert", "1");
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.metadata);
                    });

                return deferred.promise;
            };

            return backupMigrationAPI;
        }]);

        return backupMigrationAPI;
    }
);

/*
# templates/backup_migration/views/main.js           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */

define(
    'app/views/main',[
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

/*
# templates/backup_migration/index.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("whm.backupMigration", [
                "cjt2.config.whm.configProvider",
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/views/applicationController",
                    "app/views/main",
                    "app/services/backupMigrationAPI"
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.backupMigration");

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/main", {
                                controller: "main",
                                templateUrl: CJT.buildFullPath("backup_migration/views/main.ptt")
                            })
                                .otherwise({
                                    "redirectTo": "/main"
                                });
                        }
                    ]);

                    BOOTSTRAP(document, "whm.backupMigration");

                });

            return app;
        };
    }
);

