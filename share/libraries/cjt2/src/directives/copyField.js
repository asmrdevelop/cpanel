/*
# cjt/directives/copyField.js                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/modules",
        "cjt/services/alertService"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        function execCopyToClipboard(fieldID) {
            var field = document.getElementById(fieldID);
            field.focus();
            field.select();
            return document.execCommand("copy");
        }

        /**
         * Field and button combo to copy a pre-formatted text to the users clipboard
         *
         * @module copy-field
         * @restrict E
         * @memberof cjt2.directives
         *
         * @example
         * <copy-field text="copy me to your clipboard"></copy-field>
         *
         */

        var RELATIVE_PATH = "libraries/cjt2/directives/";
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

        TEMPLATE_PATH += "copyField.phtml";

        var MODULE_NAMESPACE = "cjt2.directives.copyField";
        var MODULE_REQUIREMENTS = [ "cjt2.services.alert" ];

        var CONTROLLER_INJECTABLES = ["$scope", "$timeout", "alertService"];
        var CONTROLLER = function CopyFieldController($scope, $timeout, $alertService) {

            $scope._onSuccess = function _onSuccess() {
                $alertService.success(LOCALE.maketext("Successfully copied to the clipboard."));
                $scope.copying = true;
                $timeout(function() {
                    $scope.copying = false;
                }, 3000);
            };

            $scope._execCopy = function() {
                return execCopyToClipboard($scope.copyFieldID);
            };

            /**
             *
             * Copy the text currently in the $scope.text to the clipboard
             *
             */
            $scope.copyToClipboard = function copyToClipboard() {
                if ($scope._execCopy()) {
                    $scope._onSuccess();
                }
            };

            /**
             *
             * Process updated text to determine if it is multiline or not
             *
             */
            $scope.processText = function processText() {

                if (!$scope.text) {
                    return;
                }

                var newTextParts = $scope.text.split("\n");
                if (newTextParts.length > 1) {
                    $scope.multilineRows = newTextParts.length - 1;
                }

            };

            $scope.$watch("text", $scope.processText);

            $scope.processText();

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        var DIRECTIVE_LINK = function($scope, $element, $attrs) {
            $scope.multilineRows = 1;
            $scope.copyFieldID = $scope.parentID + "_recordField";
            $scope.copying = false;
            $scope.placeholderText = $attrs.placeholder ? $attrs.placeholder : LOCALE.maketext("Nothing to copy");
            $scope.copyLabel = $attrs.copyLabel || LOCALE.maketext("Copy");
        };

        module.directive("copyField", function copyFieldDirectiveFactory() {

            return {
                templateUrl: TEMPLATE_PATH,
                scope: {
                    parentID: "@id",
                    text: "=",
                    label: "@"
                },
                restrict: "E",
                replace: true,
                transclude: true,
                link: DIRECTIVE_LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)
            };

        });

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "link": DIRECTIVE_LINK,
            "template": TEMPLATE_PATH,
            execCopyToClipboard: execCopyToClipboard
        };
    }
);
