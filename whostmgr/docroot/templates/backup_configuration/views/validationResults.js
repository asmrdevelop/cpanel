/*
# backup_configuration/views/validationResults.js  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/validationLog"
    ],
    function(angular, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        var controller = app.controller(
            "validationResults", [
                "$scope",
                "alertService",
                "validationLog",

                function(
                    $scope,
                    alertService,
                    validationLog) {

                    var logTable = new Table();

                    /**
                     * Sort ValidationLogItem Objects and update table. Items
                     * are sorted in place.
                     *
                     * @scope
                     * @method sortValidationEntries
                     */
                    $scope.sortValidationEntries = function() {
                        $scope.currentlyValidating = logTable.update();
                        $scope.meta = logTable.getMetadata();
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.currentlyValidating = validationLog.getLogEntries();

                        logTable.load($scope.currentlyValidating);

                        logTable.setSort("name,transport", "asc");

                        // remove if pagination is ever implemented
                        logTable.meta.limit = $scope.currentlyValidating.length;
                        logTable.meta.pageSize = $scope.currentlyValidating.length;

                        $scope.$watch("currentlyValidating", function() {
                            $scope.sortValidationEntries();
                            validationLog.cacheLogEntries();
                        }, true);
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
