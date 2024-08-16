/*
# templates/greylist/views/mailServices.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "uiBootstrap",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "app/services/GreylistDataSource"
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "mailServices",
            ["$scope", "GreylistDataSource", "growl", "$timeout", "$q",
                function($scope, GreylistDataSource, growl, $timeout, $q) {

                    $scope.loadingProviders = true;
                    $scope.commonMailProviders = {};
                    $scope.autotrust_new_common_mail_providers = true;

                    $scope.disableSave = function(form) {
                        var isDataUnchanged = _.isEqual($scope.commonMailProviders, GreylistDataSource.commonMailProviders) && $scope.autotrust_new_common_mail_providers === GreylistDataSource.autotrust_new_common_mail_providers;
                        return (form.$pristine || form.$invalid || isDataUnchanged);
                    };

                    $scope.changedProviders = function(trust) {
                        var providersToTrust = {};

                        for (var provider in $scope.commonMailProviders) {
                            if ($scope.commonMailProviders[provider].is_trusted === trust &&
                            GreylistDataSource.commonMailProviders.hasOwnProperty(provider) &&
                            GreylistDataSource.commonMailProviders[provider].is_trusted !== $scope.commonMailProviders[provider].is_trusted) {
                                providersToTrust[provider] = $scope.commonMailProviders[provider];
                            }
                        }

                        return providersToTrust;
                    };

                    $scope.untrustProviders = function() {

                    // no need to make an API call if all the providers are currently trusted
                        var allTrusted = $scope.areAllProvidersTrusted();
                        if (allTrusted) {
                            return;
                        }

                        var providersToUntrust = $scope.changedProviders(false);

                        if (Object.keys(providersToUntrust).length > 0) {
                            return GreylistDataSource.untrustCommonMailProviders(providersToUntrust)
                                .catch(function(error) {
                                    growl.error(error);
                                });
                        }

                        return null;
                    };

                    $scope.trustProviders = function() {

                    // no need to make an API call if all the providers are currently untrusted
                        var allUntrusted = $scope.areAllProvidersUntrusted();
                        if (allUntrusted) {
                            return;
                        }

                        var providersToTrust = $scope.changedProviders(true);

                        if (Object.keys(providersToTrust).length > 0) {
                            return GreylistDataSource.trustCommonMailProviders(providersToTrust)
                                .catch(function(error) {
                                    growl.error(error);
                                });
                        }

                        return null;
                    };

                    $scope.save = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        return $q.all([
                            $scope.trustProviders(),
                            $scope.untrustProviders(),
                            GreylistDataSource.saveCommonMailProviders($scope.commonMailProviders, $scope.autotrust_new_common_mail_providers)
                        ]).then(
                            function(result) {
                                growl.success(LOCALE.maketext("The system successfully saved your [asis,Greylisting] Common Mail Provider settings."));
                                form.$setPristine();
                            }, function(error) {
                                growl.error(error);
                            }
                        );
                    };

                    function init() {
                        GreylistDataSource.loadCommonMailProviders()
                            .then(function() {
                                $scope.commonMailProviders = {};
                                $scope.commonMailProviders = angular.copy(GreylistDataSource.commonMailProviders);
                                $scope.autotrust_new_common_mail_providers = GreylistDataSource.autotrust_new_common_mail_providers;
                                $scope.loadingProviders = false;
                            }).catch(function(response) {
                                growl.error(response.error);
                                $scope.loadingProviders = false;
                            });
                    }

                    $scope.areAllProvidersTrusted = function() {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider) && !settings[provider].is_trusted) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.areAllProvidersUntrusted = function() {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider) && settings[provider].is_trusted) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.autoUpdateNoneChecked = function() {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider) && settings[provider].autoupdate) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.autoUpdateAllChecked = function() {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider) && !settings[provider].autoupdate) {
                                return false;
                            }
                        }
                        return true;
                    };

                    $scope.trustAll = function(form, reallyTrust) {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider)) {
                                settings[provider].is_trusted = reallyTrust;
                            }
                        }
                        form.$setDirty();
                    };

                    $scope.autoUpdateAll = function(form, reallyUpdate) {
                        var settings = $scope.commonMailProviders;
                        for (var provider in settings) {
                            if (settings.hasOwnProperty(provider)) {
                                settings[provider].autoupdate = reallyUpdate;
                            }
                        }
                        form.$setDirty();
                    };

                    $scope.forceLoadMailProviders = function(form) {
                        $scope.loadingProviders = true;
                        $scope.commonMailProviders = {};
                        init();
                        form.$setPristine();
                    };

                    $scope.isCommonMailProvidersPopulated = function() {
                        return _.keys($scope.commonMailProviders).length > 0;
                    };

                    init();
                }
            ]);

        return controller;
    }
);
