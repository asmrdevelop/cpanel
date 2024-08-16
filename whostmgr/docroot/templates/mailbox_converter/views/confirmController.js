/*
# templates/mailbox_converter/views/confirmController.js
#                                                     Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "confirmController", [
                "$scope",
                "$filter",
                "indexService",
                function($scope, $filter, indexService) {

                    $scope.$parent.ready = false;
                    var _accounts = indexService.get_accounts();

                    $scope.accounts = $filter("filter")(_accounts, { "selected": 1 });
                    $scope.chosen_mailbox_format = indexService.get_format();

                    if (!$scope.chosen_mailbox_format) {
                        $scope.$parent.go(0);
                    } else if (!$scope.accounts || !$scope.accounts.length) {
                        $scope.$parent.go(1);
                    }

                    $scope.selected_accounts_msg = LOCALE.maketext("You selected [quant,_1,account,accounts] to convert to [_2].", $scope.accounts.length, $scope.chosen_mailbox_format);
                }
            ]
        );

        return controller;
    }
);
