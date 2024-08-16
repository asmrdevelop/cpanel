/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/colorsController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

require.config({
    paths: {
        "jquery-minicolors": "../../../libraries/jquery-minicolors/2.1.7/jquery.minicolors",
        "angular-minicolors": "../../../libraries/angular-minicolors/0.0.11/angular-minicolors",
    },
    shims: {
        "jquery-minicolors": {
            depends: [ "jquery" ],
        },
        "angular-minicolors": {
            depends: [ "jquery-minicolors" ],
        },
    },
});

define(
    [
        "lodash",
        "angular",
        "jquery",
        "app/constants",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "angular-minicolors",
    ],
    function(_, angular, jquery, CONSTANTS, LOCALE) {
        "use strict";

        var module = angular.module("customize.views.colorsController", [
            "customize.services.customizeService",
            "minicolors",
        ]);

        module.config([
            "minicolorsProvider",
            function(minicolorsProvider) {
                angular.extend(minicolorsProvider.defaults, {
                    control: "wheel",
                    position: "bottom left",
                    letterCase: "uppercase",
                    theme: "bootstrap",
                });
            }]
        );

        // set up the controller
        var controller = module.controller(
            "colorsController", [
                "$scope",
                "customizeService",
                "growl",
                "growlMessages",
                "savedService",
                "PAGE",
                function($scope, customizeService, growl, growlMessages, savedService, PAGE) {
                    $scope.saving = false;
                    $scope.restoring = false;
                    $scope.hexColorRegex = "^#[0-9A-Fa-f]{6}";

                    /**
                     * @typedef ColorBrandPartial
                     * @type {object}
                     * @property {object} brand
                     * @property {ColorsModel} brand.colors
                     */

                    /**
                     * @typedef ColorsModel
                     * @type {object}
                     * @property {string} primary - CSS color for the left menu
                     * @property {string} link - CSS color for links - NOT IMPLEMENT YET
                     * @property {string} accent - CSS color for various accents in the product. - NOT IMPLEMENT YET
                     */

                    // Load the prefetched data from the PAGE object.
                    $scope.model = {
                        colors: {},
                        defaults: angular.copy(CONSTANTS.DEFAULT_COLORS),
                    };

                    $scope.$watch("model.colors", function() {
                        savedService.update("colors", $scope.customization.$dirty);
                    }, true);

                    /**
                     * Blend the defaults and initial settings to get the current configuration.
                     *
                     * @param {Dictionary<string, string>} initial - initial colors from persistance layer.
                     * @param {Dictionary<string, string>} defaults - default colors for cPanel.
                     * @returns
                     */
                    function blendColors(initial, defaults) {
                        var copy = Object.assign({}, initial);
                        Object.keys(initial).forEach(function(key) {
                            if (copy[key] === "" || copy[key] === undefined || copy[key] === null) {

                                // Ignore empty keys so we keep the defaults.
                                delete copy[key];
                            }
                        });
                        var colors = Object.assign({}, defaults);
                        return Object.assign(colors, copy);
                    }

                    $scope.model.colors = blendColors( PAGE.data.jupiter.brand.colors, CONSTANTS.DEFAULT_COLORS );

                    /**
                     * Save the updates to the persistance layer.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.save = function($formCtrl) {
                        if (!$formCtrl.$valid) {
                            growl.error(LOCALE.maketext("The current customization is invalid."));
                            return;
                        }

                        growlMessages.destroyAllMessages();

                        if ($scope.saving || $scope.restoring) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;

                        /** @type {ColorBrandPartial} */
                        var partial = {
                            brand: { colors: $scope.model.colors },
                        };

                        customizeService.update(partial).then(function(update) {

                            // Update the local init values since we updated the server
                            PAGE.data.jupiter.brand.colors = angular.copy($scope.model.colors);
                            savedService.update("colors", false);
                            $formCtrl.$setPristine();

                            growl.success(LOCALE.maketext("The system successfully updated the brand colors."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update the brand colors."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Remove the brand colors from the customization.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.reset = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving || $scope.restoring) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.restoring = true;
                        return customizeService.delete("brand.colors")
                            .then(function(update) {
                                $scope.model.colors = blendColors( {}, CONSTANTS.DEFAULT_COLORS ); // Reset to defaults

                                // Update the local init values since we updated the server
                                PAGE.data.jupiter.brand.colors = angular.copy($scope.model.colors);

                                savedService.update("links", false);
                                $formCtrl.$setPristine();

                                growl.success(LOCALE.maketext("The system successfully restored the brand colors to the default."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to restore the brand colors to the default."));
                            })
                            .finally(function() {
                                $scope.restoring = false;
                            });
                    };
                },
            ]
        );

        return controller;
    }
);
