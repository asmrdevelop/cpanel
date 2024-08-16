/*
# templates/ssl_provider_manager/views/editCPStoreController.js
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
        "cjt/directives/actionButtonDirective",
        "cjt/validator/email-validator"
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "editCPStoreController", [
                "$scope",
                "editCPStoreService",
                "growl",
                function($scope, editCPStoreService, growl) {
                    function _growl_error(error) {
                        return growl.error( _.escape(error) );
                    }

                    $scope.init = function() {
                        $scope.locale = LOCALE;
                        $scope.$parent.loading = true;

                        editCPStoreService.fetch_market_providers_commission_config().then(function() {
                            $scope.cpstore_commission_config = editCPStoreService.get_market_providers_commission_config().filter( function(c) {
                                return c.provider_name === "cPStore";
                            } )[0];
                        }, _growl_error).then(function() {
                            if ($scope && $scope.$parent) {
                                $scope.$parent.loading = false;
                            }
                        });
                    };

                    $scope.set_commission_id = function(provider, commission_id) {
                        var message = LOCALE.maketext("You have set the Commission [asis,ID] for “[_1]” to “[_2]”.", _.escape(provider), _.escape(commission_id));
                        $scope.setting_commission_id = true;

                        return editCPStoreService.set_commission_id(provider, commission_id).then(function() {
                            growl.success(message);
                        }, _growl_error)
                            .then( function() {
                                $scope.setting_commission_id = false;
                            } );
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
