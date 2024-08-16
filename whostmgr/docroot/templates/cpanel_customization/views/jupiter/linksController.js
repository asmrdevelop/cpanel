/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/views/jupiter/linksController.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */

define([
    "lodash",
    "angular",
    "cjt/util/locale",
    "cjt/directives/autoFocus",
    "cjt/decorators/growlDecorator",
    "app/services/customizeService",
    "app/services/savedService",
], function(_, angular, LOCALE) {
    "use strict";

    var module = angular.module("customize.views.linksController", [
        "customize.services.customizeService",
        "customize.services.savedService",
    ]);

    var controller = module.controller("linksController", [
        "$scope",
        "customizeService",
        "savedService",
        "growl",
        "growlMessages",
        "PAGE",
        function(
            $scope,
            customizeService,
            savedService,
            growl,
            growlMessages,
            PAGE
        ) {
            $scope.saving = false;

            $scope.urlRegex =
                /^(https?):\/\/(?:[^:@]+(?::[^@]+)?@)?(?:[^\s:/?#]+|\[[a-f\\d:]+])(?::\\d+)?(?:\/[^?#]*)?(?:\\?[^#]*)?(?:#.*)?$/i;

            // Preload links
            $scope.model = {
                help: PAGE.data.jupiter.help
                    ? angular.copy(PAGE.data.jupiter.help)
                    : { url: "" },
                documentation: PAGE.data.jupiter.documentation
                    ? angular.copy(PAGE.data.jupiter.documentation)
                    : { url: "" },
            };

            // Save initial values
            $scope.initialHelpLink = $scope.model.help["url"];
            $scope.initialDocumentationLink = $scope.model.documentation["url"];

            // Watch for changes
            $scope.$watchGroup(["model.help.url", "model.documentation.url"], function(newValues) {
                var helpLinkChanged = newValues[0] !== $scope.initialHelpLink;
                var documentationLinkChanged = newValues[1] !== $scope.initialDocumentationLink;

                // If the links match their original state, make the form pristine again
                if (!helpLinkChanged && !documentationLinkChanged) {
                    growlMessages.destroyAllMessages();
                    savedService.update("links", false);
                    $scope.customization.$setPristine();
                } else {
                    savedService.update("links", $scope.customization.$dirty);
                }

            }, false);

            /**
             * Saves changes to branding customization
             * Persist the customization form if it is valid
             * @method save
             * @param {Object} $formCtrl Form control
             */
            $scope.save = function($formCtrl) {
                growlMessages.destroyAllMessages();

                if (!$formCtrl.$valid) {
                    growl.error(
                        LOCALE.maketext("The current customization is invalid.")
                    );
                    return;
                }

                if ($scope.saving) {
                    growl.warning(
                        LOCALE.maketext(
                            "The system is busy. Try again once the current operation is complete."
                        )
                    );
                    return;
                }

                $scope.saving = true;
                customizeService
                    .update({
                        documentation: {
                            url: $scope.model.documentation.url,
                        },
                        help: {
                            url: $scope.model.help.url,
                        },
                    })
                    .then(function(response) {

                        // For subsequent loads of links tab, we need to update PAGE to reflect changes
                        PAGE.data.jupiter.documentation.url =
                            $scope.model.documentation.url;
                        PAGE.data.jupiter.help.url = $scope.model.help.url;

                        $formCtrl.$setPristine();
                        savedService.update("links", false);

                        growl.success(
                            LOCALE.maketext(
                                "The system successfully updated your links."
                            )
                        );
                    })
                    .catch(function(error) {
                        growl.error(
                            LOCALE.maketext(
                                "The system failed to update your links."
                            )
                        );
                    })
                    .finally(function() {
                        $scope.saving = false;
                    });
            };
        },
    ]);

    return controller;
});
