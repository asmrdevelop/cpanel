/*
# cjt2/directives/datePicker.js                               Copyright 2022 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        /**
         * Directive to render a time picker
         *
         * @module date-picker
         * @memberof cjt2.directives
         *
         * @example
         * <date-picker ng-model="myDate"></date-picker>
         *
         */

        var RELATIVE_PATH = "libraries/cjt2/directives/";
        var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;
        var TEMPLATE = TEMPLATES_PATH + "datePicker.phtml";

        var MODULE_NAMESPACE = "cjt2.directives.datePicker";
        var MODULE_REQUIREMENTS = [];
        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        var LINK = function(scope, element, attrs, ngModel) {

            var unregister = scope.$watch(function() {
                return ngModel.$modelValue;
            }, initialize);

            function initialize(value) {
                ngModel.$setViewValue(value);
                scope.selectedDate = value;
            }

            scope.closeTextLabel = LOCALE.maketext("Close");
            scope.currentTextLabel = LOCALE.maketext("Today");
            scope.clearTextLabel = LOCALE.maketext("Clear");
            scope.showingPopup = false;
            scope.showPopup = function() {
                scope.showingPopup = true;
            };
            scope.onChange = function onChange(newDate) {
                ngModel.$setViewValue(newDate);
            };

            scope.$on("$destroy", unregister);
        };

        var DIRECTIVE_FACTORY = function createDatePickerDirective() {
            return {
                templateUrl: TEMPLATE,
                restrict: "EA",
                require: "ngModel",
                scope: {
                    parentID: "@id",
                    options: "="
                },
                transclude: true,
                link: LINK
            };
        };

        module.directive("datePicker", DIRECTIVE_FACTORY);

        return {
            "directiveFactory": DIRECTIVE_FACTORY,
            "linkController": LINK,
            "namespace": MODULE_NAMESPACE,
            "template": TEMPLATE
        };
    }
);
