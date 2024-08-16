/*
# cjt/directives/searchDirective.js                                              Copyright(c) 2020 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/directives/preventDefaultOnEnter",
        "cjt/directives/autoFocus",
        "cjt/filters/qaSafeIDFilter",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE) {

        var DEFAULT_PLACEHOLDER = LOCALE.maketext("Search");
        var DEFAULT_TITLE = LOCALE.maketext("Search");
        var DEFAULT_AUTO_FOCUS = false;
        var DEFAULT_DEBOUNCE = 250;
        var RELATIVE_PATH = "libraries/cjt2/directives/searchDirective.phtml";

        var module = angular.module("cjt2.directives.search", [
            "cjt2.templates",
            "cjt2.directives.preventDefaultOnEnter",
            "cjt2.directives.autoFocus"
        ]);

        module.directive("search", function() {

            return {
                restrict: "E",
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                require: "ngModel",
                replace: true,
                scope: {
                    parentID: "@id",
                    placeholder: "@?placeholder",
                    autofocus: "@?autofocus",
                    title: "@?title",
                    debounce: "@?debounce"
                },
                compile: function() {

                    return {
                        pre: function(scope, element, attrs) { // eslint-disable-line no-unused-vars
                            if (angular.isUndefined(attrs.placeholder)) {
                                attrs.placeholder = DEFAULT_PLACEHOLDER;
                            }
                            if (angular.isUndefined(attrs.title)) {
                                attrs.title = DEFAULT_TITLE;
                            }

                            if (angular.isUndefined(attrs.autofocus)) {
                                attrs.autofocus = DEFAULT_AUTO_FOCUS;
                            } else {
                                attrs.autofocus = true;
                            }

                            if (angular.isUndefined(attrs.debounce)) {
                                attrs.debounce = DEFAULT_DEBOUNCE;
                            }

                            scope.autofocus = attrs.autofocus;
                            scope.placeholder = attrs.placeholder;
                            scope.title = attrs.title;
                            scope.debounce = Number(attrs.debounce);
                            scope.ariaLabelSearch = LOCALE.maketext("Search");
                            scope.ariaLabelClear = LOCALE.maketext("Clear");
                            scope.modelOptions = { debounce: scope.debounce };
                        },
                        post: function(scope, element, attrs, ctrls) { // eslint-disable-line no-unused-vars
                            var ngModelCtrl = ctrls;

                            if (!ngModelCtrl) {
                                return; // do nothing if no ng-model on the directive
                            }

                            ngModelCtrl.$render = function() {
                                scope.filterText = ngModelCtrl.$viewValue;
                            };

                            scope.clear = function(event) {
                                if (event.keyCode === 27) {
                                    scope.filterText = "";
                                }
                            };

                            scope.$watch("filterText", function() {
                                ngModelCtrl.$setViewValue(scope.filterText);
                            });

                        }
                    };
                }
            };
        });

        return {
            DEFAULT_PLACEHOLDER: DEFAULT_PLACEHOLDER,
            RELATIVE_PATH: RELATIVE_PATH,
            DEFAULT_DEBOUNCE: DEFAULT_DEBOUNCE,
        };
    }
);
