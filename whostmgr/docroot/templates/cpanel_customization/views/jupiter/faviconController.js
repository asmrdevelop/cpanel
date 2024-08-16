/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/faviconController.js
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
        "cjt/decorators/growlDecorator",
        "app/directives/fileUpload",
        "app/services/customizeService",
        "app/services/savedService",
    ],
    function(_, angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.views.faviconController", [
            "customize.directives.fileUpload",
            "customize.services.customizeService",
            "customize.services.savedService",
            "customize.directives.fileUpload",
        ]);

        // set up the controller
        var controller = module.controller(
            "faviconController", [
                "$scope",
                "customizeService",
                "savedService",
                "growl",
                "growlMessages",
                "PAGE",
                function($scope, customizeService, savedService, growl, growlMessages, PAGE) {

                    $scope.saving = false;
                    $scope.MAX_FILE_SIZE = CONSTANTS.MAX_FILE_SIZE;
                    $scope.LOCALE = LOCALE;

                    // Load the prefetched data from the PAGE object.
                    var favicon = PAGE.data.jupiter.brand.favicon;

                    /**
                     * @typedef FileModel
                     * @private
                     * @property {string} filename - name of the file to display
                     * @property {string} data - base 64 encoded file contents
                     * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                     */

                    /**
                     * @typedef FaviconModel
                     * @property {FileModel} favicon - storage for the favicon for the site.
                     * @property {FileModel} forDarkBackground - storage for the logo used on dark backgrounds.
                     * @property {string} description - description for use with the logos as the title property.
                     */
                    $scope.model = {
                        favicon: {
                            data: favicon ? CONSTANTS.EMBEDDED_ICO + favicon : "",
                            filename: favicon ? "favicon.ico" : "",
                            saved: !!favicon,
                        },
                    };

                    // Watch for changes
                    $scope.$watch("model.favicon", function() {
                        savedService.update("favicon", $scope.customization.$dirty);
                    }, true);


                    /**
                     * Save the favicon data from the tab.
                     *
                     * @async
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

                        var favicon = $scope.model.favicon.data.replace(CONSTANTS.DATA_URL_PREFIX_REGEX, "");

                        return customizeService.update({
                            brand: {
                                favicon: favicon,
                            },
                        }).then(function(update) {
                            $scope.model.favicon.filename = "favicon.ico";
                            $scope.model.favicon.saved = true;

                            // Update the initial data
                            PAGE.data.jupiter.brand.favicon = favicon;

                            $formCtrl.$setPristine();
                            savedService.update("favicon", false);

                            growl.success(LOCALE.maketext("The system successfully updated the favicon."));
                        }).catch(function(error) {
                            growl.error(LOCALE.maketext("The system failed to update the favicon."));
                        }).finally(function() {
                            $scope.saving = false;
                        });
                    };

                    /**
                     * Reset the favicon to a pristine state after a delete before saving.
                     *
                     * @param {FormController} $formCtrl
                     */
                    $scope.reset = function($formCtrl) {
                        growlMessages.destroyAllMessages();
                        $formCtrl.file_upload_favicon_file.$setPristine();
                        savedService.update("favicons", false);
                    };

                    /**
                     * Remove the favorite icon from the customizations.
                     *
                     * @param {FormController} $formCtrl - the file to delete from the persistance layer.
                     */
                    $scope.delete = function($formCtrl) {
                        growlMessages.destroyAllMessages();

                        if ($scope.saving) {
                            growl.warning(LOCALE.maketext("The system is busy. Try again once the current operation is complete."));
                            return;
                        }

                        $scope.saving = true;
                        return customizeService.delete("brand.favicon")
                            .then(function(update) {
                                $scope.model.favicon.saved = false;
                                $scope.model.favicon.data = "";
                                $scope.model.favicon.filename = "";

                                // Update the initial data
                                PAGE.data.jupiter.brand.favicon = "";

                                $formCtrl.$setPristine();
                                savedService.update("favicon", false);

                                growl.success(LOCALE.maketext("The system successfully removed the custom favicon and restored the default [asis,cPanel] favicon."));
                            })
                            .catch(function(error) {
                                growl.error(LOCALE.maketext("The system failed to remove the custom favicon."));
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
