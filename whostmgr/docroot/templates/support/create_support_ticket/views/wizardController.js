/*
 * whostmgr/docroot/templates/support/create_support_ticket/views/wizardController.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var app = angular.module("whm.createSupportTicket");

        app.controller("wizardController", [
            "$scope",
            "wizardState",
            "wizardApi",
            function($scope, wizardState, wizardApi) {
                $scope.wizard = wizardState;
                $scope.wizardApi = wizardApi;
                wizardApi.configure({
                    resetFn: function(suppressViewLoading) {
                        wizardState.step = 0;
                        if (!suppressViewLoading) {
                            wizardApi.loadView("/start");
                        }
                        wizardApi.hideFooter();
                        return true;
                    }
                });
            }
        ]);
    }
);
