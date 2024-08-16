/*
# templates/external_auth/views/ManageUserController.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "ngSanitize",
        "cjt/modules",
        "app/services/ProvidersService",
        "app/services/UsersService",
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        function ManageUserController($scope, $routeParams, $location, $rootScope, $uibModal, ProvidersService, UsersService, growl) {
            $scope.user = false;
            $scope.LOCALE = LOCALE;

            $scope.init = function() {

                $scope.loadingUser = true;
                $scope.userID = $routeParams.userID;

                $scope.user = UsersService.get_user_by_username($scope.userID);
                $scope.user_links = $scope.get_user_links();

                $scope.loadingUser = false;

            };

            $scope.fetch = function() {
                $scope.user_links = [];
                $scope.loadingUser = true;
                UsersService.fetch_users().then(function() {
                    $scope.user = UsersService.get_user_by_username($scope.userID);
                    $scope.user_links = $scope.get_user_links();
                    if (!$scope.user_links.length) {
                        $location.path("/users");
                    }
                }, function(error) {
                    growl.error(LOCALE.maketext("The system encountered an error while it tried to retrieve the users: [_1]", error));
                }).finally(function() {
                    $scope.loadingUser = false;
                });
            };

            $scope.unlink_provider = function(subject_unique_identifier, provider_id) {
                var provider = ProvidersService.get_provider_by_id(provider_id);
                var modalScope = $rootScope.$new();
                modalScope.provider = provider.display_name;
                modalScope.username = $scope.user.username;

                var preferred_username = $scope.user.links.openid_connect[provider_id][subject_unique_identifier].preferred_username;

                $scope.modalInstance = $uibModal.open({
                    templateUrl: "confirmproviderunlink.html",
                    scope: modalScope
                });
                return $scope.modalInstance.result.then(function() {
                    return UsersService.unlink_provider($scope.user.username, subject_unique_identifier, provider.id).then(function() {
                        growl.success(LOCALE.maketext("The system has removed the “[_1] ([_2])” authentication linkage for “[_3].”", provider.display_name, preferred_username, $scope.user.username));
                        $scope.fetch();
                    }, function(error) {
                        growl.error(LOCALE.maketext("The system could not remove the “[_1] ([_2])” authentication linkage for “[_3]” due to an error: [_4]", provider.display_name, preferred_username, $scope.user.username, error));
                    });
                }, function() {
                    $scope.clear_modal_instance();
                }).finally(function() {
                    $scope.clear_modal_instance();
                });
            };

            $scope.clear_modal_instance = function() {
                if ($scope.modalInstance) {
                    $scope.modalInstance.close();
                    $scope.modalInstance = null;
                }
            };
            $scope.get_user_links = function() {
                var providers = [];

                if (!$scope.user) {
                    return providers;
                }
                angular.forEach($scope.user.links, function(provider_type) {
                    angular.forEach(provider_type, function(links, key) {
                        var provider = ProvidersService.get_provider_by_id(key);
                        if (!providers[key]) {
                            providers.push(provider);
                        }

                        angular.forEach(links, function(subscriber_account, subject_unique_identifier) {
                            providers.push({
                                provider_key: provider.id,
                                display_name: subscriber_account.preferred_username,
                                subject_unique_identifier: subject_unique_identifier
                            });
                        });

                    });
                });
                return providers;
            };

            $scope.return_to_list = function() {
                $location.path("/users");
            };

            $scope.init();

        }
        ManageUserController.$inject = ["$scope", "$routeParams", "$location", "$rootScope", "$uibModal", "ProvidersService", "UsersService", "growl"];
        app.controller("ManageUserController", ManageUserController);


    });
