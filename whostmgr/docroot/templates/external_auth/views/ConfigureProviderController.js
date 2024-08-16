/*
# templates/external_auth/views/ConfigureProviderController.js
#                                                        Copyright 2022 cPanel, L.L.C.
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
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/validator/datatype-validators",
        "ngSanitize",
        "cjt/modules",
        "app/services/ProvidersService"
    ],
    function(angular, $, _, LOCALE) {
        "use strict";

        var app = angular.module("App");

        function ConfigureProviderController($scope, $routeParams, $location, ProvidersService, growl) {
            $scope.fields = {};
            $scope.configurations = {};
            $scope.provider = false;
            $scope.confirmed_redirects = false;
            $scope.savingProvider = false;
            $scope.services = {};
            $scope.service_names = {
                "webmaild": "Webmail",
                "whostmgrd": "WHM",
                "cpaneld": "cPanel"
            };

            function _growl_error(error) {
                growl.error( _.escape(error) );
            }

            $scope.init = function() {

                $scope.loadingProvider = true;

                var providerID = $routeParams.providerID;
                $scope.provider = ProvidersService.get_provider_by_id(providerID);

                if (!$scope.provider) {
                    $location.path("providers");
                }

                ProvidersService.get_provider_configuration_fields($scope.provider.id).then(function(result) {
                    $scope.fields = result.data;
                    return ProvidersService.get_provider_client_configurations($scope.provider.id);
                }).then(function(result) {
                    var baseObject = {};
                    angular.forEach($scope.fields, function(value) {
                        baseObject[value.field_id] = "";
                    }, baseObject);
                    $scope.configurations = angular.extend(baseObject, result.data.client_configurations);
                    return ProvidersService.get_provider_display_configurations($scope.provider.id);
                }, _growl_error).then(function(result) {
                    angular.forEach(result.data, function(service) {
                        $scope.services[service.service] = service;
                    });
                }, _growl_error).finally(function() {
                    $scope.loadingProvider = false;
                });

            };

            $scope.saveProviderConfigurations = function() {
                var saveable_configs = {};

                $scope.savingProvider = true;

                var display_configs = [];

                // Other possible, but not exposed params
                // "display_name" : "Test Google",
                // "documentation_url" : "docs_url",
                // "label" : "Log in with a Google+ Account",
                // "link" : ignore(),
                // "provider_name" : "testgoogle",
                angular.forEach($scope.services, function(service) {
                    display_configs.push({
                        "provider_id": $scope.provider.id,
                        "service_name": service.service,
                        "configs": {
                            "color": service.color,
                            "icon": service.icon,
                            "icon_type": service.icon_type,
                            "textcolor": service.textcolor,
                            "label": service.label
                        }
                    });
                });

                angular.forEach($scope.fields, function(value) {
                    saveable_configs[value.field_id] = $scope.configurations[value.field_id];
                });

                return ProvidersService.save_provider_configurations($scope.provider.id, saveable_configs, display_configs).then(function() {
                    $location.path("providers");
                    growl.success(LOCALE.maketext("The system successfully updated the configurations for “[_1].”", $scope.provider.display_name));
                }, function(error) {
                    growl.error(LOCALE.maketext("The system could not update the configurations for “[_1].” The following error occurred: “[_2]”", $scope.provider.display_name, error));
                }).finally(function() {
                    $scope.savingProvider = false;
                });
            };

            $scope.canSave = function(editorForm) {

                var field;
                for (var i = 0; i < $scope.fields.length; i++) {
                    field = $scope.fields[i];

                    if (!field.optional && !$scope.configurations[field.field_id]) {
                        return false;
                    }
                }

                if ($scope.configurations["redirect_uris"] && !editorForm.confirmed_redirects.$modelValue) {
                    return false;
                }

                return true;

            };

            $scope.init();
            window.scope = $scope;

        }
        ConfigureProviderController.$inject = ["$scope", "$routeParams", "$location", "ProvidersService", "growl"];
        app.controller("ConfigureProviderController", ConfigureProviderController);


    });
