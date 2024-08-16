/*
# templates/twofactorauth/views/configController.js
#                                                  Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

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
        "app/services/tfaData"
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "configController",
            ["$scope", "TwoFactorData", "growl", "$timeout", "PAGE",
                function($scope, TwoFactorData, growl, $timeout, PAGE) {

                    var CC = this;

                    CC.issuer = TwoFactorData.issuer;
                    CC.systemWideIssuer = TwoFactorData.systemWideIssuer;
                    CC.saveInProgress = false;
                    CC.loadingIssuer = false;
                    CC.saveError = false;
                    CC.currentUser = TwoFactorData.currentUser;

                    CC.disableSave = function(form) {
                        return (CC.saveInProgress || (form.$dirty && form.$invalid));
                    };

                    CC.issuerHelpText = LOCALE.maketext("The name associated with the service provider.");
                    CC.issuerPlaceholder = LOCALE.maketext("Provide a name for the authentication service.");
                    CC.rootIssuerPlaceholder = PAGE.server_hostname;

                    CC.systemWideIssuerAlert = function() {
                        var issuer = CC.systemWideIssuer.replace(/ /g, "&nbsp;");
                        return LOCALE.maketext("If you do not provide an issuer, the system will use: “[output,strong,_1]”", issuer);
                    };

                    CC.saveIssuer = function(form) {

                    // update the model values
                        setAllInputsDirty(form);

                        if (!form.$valid) {
                            return;
                        }

                        CC.saveInProgress = true;

                        return TwoFactorData.saveIssuer(CC.issuer)
                            .then(
                                function() {
                                    CC.systemWideIssuer = TwoFactorData.systemWideIssuer;
                                    growl.success(LOCALE.maketext("The system successfully saved the issuer name."));
                                    CC.saveError = false;
                                }, function(error) {
                                    CC.saveError = true;
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    CC.saveInProgress = false;
                                }
                            );
                    };

                    CC.getIssuer = function() {
                        CC.loadingIssuer = true;
                        return TwoFactorData.getIssuer()
                            .then(
                                function() {
                                    CC.issuer = TwoFactorData.issuer;
                                    CC.systemWideIssuer = TwoFactorData.systemWideIssuer;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    CC.loadingIssuer = false;
                                }
                            );
                    };

                    CC.init = function() {
                        if (!CC.issuer) {
                            CC.getIssuer();
                        }

                        // We need to initialize the form inside of a timeout
                        // so that we have enough time for the form to load
                        // with data.
                        $timeout(function() {

                        // re-check all the inputs to verify that we are not given
                        // bad data on our initial load
                            setAllInputsDirty(CC.config_form);
                        });


                    };

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


                    CC.init();
                }
            ]);

        return controller;
    }
);
