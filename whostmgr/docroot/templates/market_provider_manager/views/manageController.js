/*
# templates/ssl_provider_manager/views/manageController.js
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
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/validator/email-validator",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
    ],
    function(_, angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "manageController", [
                "$scope",
                "manageService",
                "editCPStoreService",
                "growl",
                function($scope, manageService, editCPStoreService, growl) {
                    function _growl_error(error) {
                        return growl.error( _.escape(error) );
                    }

                    $scope.set_provider = function(provider, enabled) {
                        var enable_message = LOCALE.maketext("The system successfully enabled the Market provider “[_1]”.", _.escape(provider.name));
                        var disabled_message = LOCALE.maketext("The system successfully disabled the Market provider “[_1]”.", _.escape(provider.name));
                        var success_message = enabled ? enable_message : disabled_message;

                        return manageService.set_provider_enabled_status(provider, enabled).then(function() {
                            growl.success(success_message);

                            if (enabled && provider.supports_commission) {
                                var promise = check_for_commission_id_and_set_if_does_not_exist(provider.name);
                                return promise.then(function(success) {
                                    provider.enabled = enabled;
                                    $scope.$parent.go("edit_cpstore_config", 2);
                                }, function(error) {
                                    provider.enabled = enabled;
                                    $scope.$parent.go("edit_cpstore_config", 2);
                                });
                            } else {
                                provider.enabled = enabled;
                            }
                        }, _growl_error);
                    };

                    var check_for_commission_id_and_set_if_does_not_exist = function(provider) {
                        return editCPStoreService.fetch_market_providers_commission_config().then(function(success) {
                            var provider_needs_commission_id = false;
                            for (var x = 0; x < success.data.length; x++ ) {
                                if (success.data[x].provider_name === provider && !success.data[x].remote_commission_id) {
                                    provider_needs_commission_id = true;
                                }
                            }
                            if ( provider_needs_commission_id && $scope.CONTACTEMAIL ) {

                                // if no remote commission id, set one, otherwise we're done
                                return editCPStoreService.set_commission_id(provider, $scope.CONTACTEMAIL).then(function(success) {
                                    growl.success(LOCALE.maketext("The system successfully set the commission [asis,ID] for the provider “[_1]” to “[_2]”.", _.escape(provider), _.escape($scope.CONTACTEMAIL)));
                                }, function(error) {

                                    // We silence errors because they just might not be able to set it to an email
                                });
                            }
                        }, _growl_error);
                    };

                    $scope.init = function() {
                        $scope.fetching_products = true;
                        $scope.locale = LOCALE;
                        $scope.providers = manageService.get_providers();
                        $scope.$parent.loading = true;

                        manageService.fetch_products().then(function(result) {
                            angular.forEach(result.meta.warnings, function(value) {
                                growl.warning( _.escape(value) );
                            });
                            $scope.products = manageService.get_products();
                        }, _growl_error).finally(function() {
                            if ($scope && $scope.$parent) {
                                $scope.$parent.loading = false;
                            }
                            $scope.fetching_products = false;

                        });

                        manageService.fetch_contact_email().then(function() {
                            $scope.CONTACTEMAIL = manageService.get_contact_email();
                        }, _growl_error);
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
