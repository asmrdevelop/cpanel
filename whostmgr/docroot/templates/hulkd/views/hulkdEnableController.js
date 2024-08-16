/*
# templates/hulkd/views/hulkdEnableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                      http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/services/HulkdDataSource"
    ],
    function(angular, $, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "hulkdEnableController",
            ["$scope", "HulkdDataSource", "growl", "growlMessages", "PAGE",
                function($scope, HulkdDataSource, growl, growlMessages, PAGE) {
                    $scope.hulkdEnabled = PARSE.parsePerlBoolean(PAGE.hulkd_status.is_enabled);

                    $scope.knobLabel = "\u00a0";

                    $scope.changing_status = false;
                    $scope.status_check_in_progress = false;

                    $scope.handle_keydown = function(event) {

                    // prevent the spacebar from scrolling the window
                        if (event.keyCode === 32) {
                            event.preventDefault();
                        }
                    };

                    $scope.handle_keyup = function(event) {

                    // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            $scope.toggle_status();
                        }
                    };

                    $scope.toggle_status = function() {
                        if ($scope.changing_status) {
                            return;
                        }

                        $scope.changing_status = true;

                        if ($scope.hulkdEnabled) {
                            growlMessages.destroyAllMessages();
                            HulkdDataSource.disable_hulkd()
                                .then( function() {
                                    $scope.hulkdEnabled = false;
                                    growl.success(LOCALE.maketext("[asis,cPHulk] is now disabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        } else {
                            HulkdDataSource.enable_hulkd()
                                .then( function(response) {
                                    $scope.hulkdEnabled = true;
                                    growl.success(LOCALE.maketext("[asis,cPHulk] is now enabled."));
                                    if (response.data && response.data.restart_ssh) {
                                        growl.warning(LOCALE.maketext("The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.", PAGE.security_token + "/scripts/ressshd", { "target": "_blank" }));
                                    } else if (response.data && response.data.warning) {
                                        growl.warning(response.data.warning);
                                    }
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        }

                    };

                    $scope.get_status = function() {
                        if ($scope.status_check_in_progress) {
                            return;
                        }
                        $scope.status_check_in_progress = true;
                        return HulkdDataSource.hulkd_status()
                            .then( function(results) {
                                if (results !== $scope.hulkdEnabled) {

                                // this test needs to run only if status has changed
                                    if (results === false) {
                                        growlMessages.destroyAllMessages();
                                    }
                                    growl.warning(LOCALE.maketext("The status for [asis,cPHulk] has changed, possibly in another browser session."));
                                }
                                $scope.hulkdEnabled = results;
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.status_check_in_progress = false;
                            });
                    };

                    $scope.init = function() {
                        $(document).ready(function() {

                        // for window and tab changes
                            $(window).on("focus", function() {
                                $scope.get_status();
                            });
                        });
                    };

                    $scope.init();
                }
            ]);

        return controller;
    }
);
