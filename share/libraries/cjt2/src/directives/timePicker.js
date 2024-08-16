/*
# cjt2/directives/timePicker.js                               Copyright 2022 cPanel, L.L.C.
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
         * @module time-picker
         * @memberof cjt2.directives
         *
         * @example
         * <time-picker></time-picker>
         *
         */

        var RELATIVE_PATH = "libraries/cjt2/directives/";
        var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;
        var TEMPLATE = TEMPLATES_PATH + "timePicker.phtml";

        var MODULE_NAMESPACE = "cjt2.directives.timePicker";
        var module = angular.module(MODULE_NAMESPACE, []);

        var LINK = function(scope, element, attrs, ngModel) {

            scope.options = angular.extend({
                min: 0
            }, scope.options);

            var unregister = scope.$watch(function() {
                return ngModel.$modelValue;
            }, initialize);

            function initialize(value) {
                ngModel.$setViewValue(value);
                scope.selectedTime = value;
            }

            scope.hStep = 1;
            scope.mStep = 15;
            scope.showMeridian = false;

            scope.onChange = function onChange(newDate) {
                ngModel.$setViewValue(newDate);
            };

            scope.$on("$destroy", unregister);
        };

        var DIRECTIVE_FACTORY = function createTimePickerDirective() {
            return {
                templateUrl: TEMPLATE,
                restrict: "EA",
                require: "ngModel",
                scope: {
                    parentID: "@id",
                    options: "=",
                },
                transclude: true,
                link: LINK
            };
        };

        module.directive("timePicker", DIRECTIVE_FACTORY);

        return {
            "directiveFactory": DIRECTIVE_FACTORY,
            "linkController": LINK,
            "namespace": MODULE_NAMESPACE,
            "template": TEMPLATE
        };
    }
);
