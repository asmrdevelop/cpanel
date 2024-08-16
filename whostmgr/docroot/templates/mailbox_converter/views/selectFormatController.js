/*
# templates/killacct/views/selectFormatController.js
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
            "selectFormatController", [
                "$scope",
                "indexService",
                function($scope, indexService) {

                    $scope.$parent.ready = false;
                    $scope.selected_format = indexService.get_format();
                    var _accounts = indexService.get_accounts();

                    if ($scope.selected_format) {
                        $scope.$parent.ready = true;
                    }

                    var _maildir_count = {};
                    _accounts.forEach(function(item) {
                        if (item.mailbox_format in _maildir_count) {
                            _maildir_count[item.mailbox_format] += 1;
                        } else {
                            _maildir_count[item.mailbox_format] = 1;
                        }
                    });

                    $scope.maildir_count = _maildir_count;

                    $scope.select = function(format) {
                        $scope.selected_format = indexService.set_format(format);
                        $scope.$parent.ready = true;
                    };

                    $scope.format_is = function(format) {
                        return format === $scope.selected_format;
                    };

                    $scope.number_of_accounts_msg = function(type) {
                        return LOCALE.maketext("[quant,_1,account,accounts,No accounts] [numerate,_1,uses,use] this format.", $scope.maildir_count[type] || 0);
                    };
                }
            ]
        );

        return controller;
    }
);
