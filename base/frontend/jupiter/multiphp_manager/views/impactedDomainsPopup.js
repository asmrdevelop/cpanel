/*
 * templates/multiphp_manager/views/impactedDomainsPopup.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "impactedDomainsPopup",
            ["$scope", "$uibModalInstance", "data",
                function($scope, $uibModalInstance, data) {
                    $scope.modalData = {};
                    var vhostInfo = data;
                    $scope.modalData = vhostInfo;

                    $scope.closeModal = function() {
                        $uibModalInstance.close();
                    };
                }
            ]);
        return controller;
    }
);
