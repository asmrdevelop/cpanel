/*
# templates/greylist/views/config.js               Copyright(c) 2020 cPanel, L.L.C.
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
            "configController",
            ["$scope", "GreylistDataSource", "growl", "$timeout",
                function($scope, GreylistDataSource, growl, $timeout) {

                    $scope.configSettings = GreylistDataSource.configSettings;

                    $scope.disableSave = function(form) {
                        return (form.$dirty && form.$invalid);
                    };

                    $scope.timeoutHelpText = LOCALE.maketext("The number of minutes during which the mail server defers email from an unknown triplet.");
                    $scope.waitHelpText = LOCALE.maketext("The number of minutes during which the mail server accepts a resent email from an unknown triplet.");
                    $scope.expiresHelpText = LOCALE.maketext("The time at which the mail server treats a resent email as coming from a new, unknown triplet.");
                    $scope.spfHelpText = LOCALE.maketext("Whether the system automatically accepts email from hosts with a valid [asis,SPF] record.[comment,this text is used in a tooltip]");

                    $scope.save = function(form) {

                    // update the model values
                        setAllInputsDirty(form);

                        if (!form.$valid) {
                            return;
                        }

                        return GreylistDataSource.saveConfigSettings($scope.configSettings)
                            .then(
                                function() {
                                    growl.success(LOCALE.maketext("The system successfully saved your [asis,Greylisting] configuration settings."));
                                }, function(error) {
                                    growl.error(error);
                                }
                            );
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        init();
                    });


                    function init() {

                    // We need to initialize the form inside of a timeout
                    // so that we have enough time for the form to load
                    // with data.
                        $timeout(function() {
                            $scope.configSettings = GreylistDataSource.configSettings;

                            // re-check all the inputs to verify that we are not given
                            // bad data on our initial load
                            setAllInputsDirty($scope.config_form);
                        });
                    }

                    function setAllInputsDirty(form) {
                        var keys = _.keys(form);
                        for (var i = 0, len = keys.length; i < len; i++) {
                            var value = form[keys[i]];

                            // A form input will have the $setViewValue property.
                            // Setting inputs to $dirty, but re-applying its content in itself.
                            // This will trigger the validation (if any) on each form element.
                            if (value && value.$setViewValue) {
                                value.$setViewValue(value.$viewValue);
                            }
                        }
                    }

                }
            ]);

        return controller;
    }
);
