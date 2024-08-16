/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/logoController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "app/constants",
        "cjt/directives/autoFocus",
        "cjt/decorators/growlDecorator",
        "app/directives/fileUpload",
        "app/services/customizeService",
        "app/services/savedService",
    ],
    function(_, angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.views.logoController", [
            "customize.services.customizeService",
            "customize.directives.fileUpload",
            "customize.services.savedService",
        ]);

        var controller = module.controller(
            "logoController", [
                "$scope",
                "customizeService",
                "savedService",
                "growl",
                "growlMessages",
                "PAGE",
                function($scope, customizeService, savedService, growl, growlMessages, PAGE) {
                    $scope.saving = false;

                    // Load the prefetched data from the PAGE object.
                    var lightLogo = PAGE.data.jupiter.brand.logo.forLightBackground;
                    var darkLogo = PAGE.data.jupiter.brand.logo.forDarkBackground;
                    var description = PAGE.data.jupiter.brand.logo.description;

                    /**
                     * @typedef FileModel
                     * @property {string} filename - name of the file to display
                     * @property {string} data - base 64 encoded file contents
                     * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                     * @property {string} name - name of the property
                     */

                    /**
                     * @typedef LogosModel
                     * @property {FileModel} forLightBackground - storage for the logo use on light backgrounds.
                     * @property {FileModel} forDarkBackground - storage for the logo used on dark backgrounds.
                     * @property {string} description - description for use with the logos as the title property.
                     */
                    $scope.model = {
                        forLightBackground: {
                            data: lightLogo ? CONSTANTS.EMBEDDED_SVG + lightLogo : "",
                            filename: lightLogo ? "logo-light.svg" : "",
                            saved: !!lightLogo,
                            name: "forLightBackground",
                        },
                        forDarkBackground: {
                            data: darkLogo ? CONSTANTS.EMBEDDED_SVG + darkLogo : "",
                            filename: darkLogo ? "logo-dark.svg" : "",
                            saved: !!darkLogo,
                            name: "forDarkBackground",
                        },
                        description: description || "",
                    };

                    $scope.MAX_FILE_SIZE = CONSTANTS.MAX_FILE_SIZE;
                    $scope.LOCALE = LOCALE;

                    // Watch for changes
                    $scope.$watch("model.forLightBackground", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, true);

                    $scope.$watch("model.forDarkBackground", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, true);

                    $scope.$watch("model.description", function() {
                        savedService.update("logos", $scope.customization.$dirty);
                    }, false);

                    /**
                     * @typedef backgroundColors
                     * @property {string} primaryDark - the background color the logo in full screen.
                     * @property {string} primaryLight - the background color for the logo in mobile.
                     */
                    $scope.backgroundColors = {
                        primaryDark: PAGE.data.jupiter.brand.colors.primary || CONSTANTS.DEFAULT_PRIMARY_DARK,

                        // NOTE: There does not seem to be an override for mobile background for the logo
                        primaryLight: CONSTANTS.DEFAULT_PRIMARY_LIGHT,
                    };

                    /**
                     * Save the logo data from the tab.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.save = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if (!$formCtrl.$valid) {
                            growl.error(LOCALE.maketext("The current customization is invalid."));
                            return;
                        }

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;

                        var forDarkBackground = $scope.model.forDarkBackground.data;
                        if (forDarkBackground) {
                            forDarkBackground = forDarkBackground.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");
                        }
                        var forLightBackground = $scope.model.forLightBackground.data;
                        if (forLightBackground) {
                            forLightBackground = forLightBackground.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");
                        }

                        customizeService.update({
                            brand: {
                                logo: {
                                    forLightBackground: forLightBackground,
                                    forDarkBackground: forDarkBackground,
                                    description: $scope.model.description,
                                },
                            },
                        }).then(function(update) {
                            if (forDarkBackground) {
                                $scope.model.forDarkBackground.filename = "logo-dark.svg";
                                $scope.model.forDarkBackground.saved = true;

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo.forDarkBackground = forDarkBackground;
                            }
                            if (forLightBackground) {
                                $scope.model.forLightBackground.filename = "logo-light.svg";
                                $scope.model.forLightBackground.saved = true;

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo.forLightBackground = forLightBackground;
                            }

                            // Update the initial data
                            PAGE.data.jupiter.brand.logo.description = $scope.model.description;

                            $formCtrl.$setPristine();
                            savedService.update("logos", false);

                            growl.success(LOCALE.maketext("The system successfully updated the logos."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update your logos."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Evaluate the state of the inputs and update the $pristine state of the form.
                     *
                     * NOTE:
                     * angular.js does not reevalute the form.$isPristine flag when the child inputs
                     * are set to pristine individually. We must loop over the list of controls ourselves
                     * and the set this property.
                     * @param {FormController} $formCtrl
                     */
                    var updateFormState = function($formCtrl) {
                        var controls = ["file_upload_logo_dark_file", "file_upload_logo_light_file", "icon_description"];
                        var isPristine = true; // Assume pristine, unless there is evidence otherwise.
                        controls.forEach(function(inputName) {
                            if ($formCtrl[inputName].$dirty) {
                                isPristine = false;
                            }
                        });
                        if (isPristine) {
                            $formCtrl.$setPristine();
                        }
                    };

                    /**
                     * Reset the logo to a pristine state after a delete before saving.
                     *
                     * @param {FormController} $formCtrl
                     * @param {string} which
                     */
                    $scope.reset = function($formCtrl, which) {
                        growlMessages.destroyAllMessages();
                        switch (which) {
                            case "forDarkBackground":
                                $formCtrl.file_upload_logo_dark_file.$setPristine();
                                break;
                            case "forLightBackground":
                                $formCtrl.file_upload_logo_light_file.$setPristine();
                                break;
                        }
                        updateFormState($formCtrl);
                        savedService.update("logos", $formCtrl.$dirty);
                    };

                    /**
                     * Remove the specific logo from the
                     * @param {FormController} $formCtrl
                     * @param {string} which - the name of the image field to delete
                     */
                    $scope.delete = function($formCtrl, which) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;
                        return customizeService.delete("brand.logo." + which)
                            .then(function(update) {
                                $scope.model[which].saved = false;
                                $scope.model[which].data = "";
                                $scope.model[which].filename = "";

                                // Update the initial data
                                PAGE.data.jupiter.brand.logo[which] = "";

                                // Reset the part of the form that was persisted.
                                switch (which) {
                                    case "forDarkBackground":
                                        $formCtrl.file_upload_logo_dark_file.$setPristine();
                                        break;
                                    case "forLightBackground":
                                        $formCtrl.file_upload_logo_light_file.$setPristine();
                                        break;
                                }
                                savedService.update("logos", $formCtrl.$dirty);

                                growl.success(LOCALE.maketext("The system successfully removed the logo."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to remove the logo."));
                            })
                            .finally(function() {
                                $scope.saving = false;
                            });
                    };
                },
            ]
        );

        return controller;
    }
);
