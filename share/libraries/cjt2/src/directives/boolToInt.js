/*
# cjt/directives/boolToInt.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        var module = angular.module("cjt2.directives.boolToInt", []);

        /**
         * The boolToInt directive is used for better Perl to frontend handling
         *
         * @directive
         * @directiveType Attribute
         * Angular directive that when attached to an element with an ng-model will render that model as true or false
         * but ensure that any changing will result in 1 or 0 values.  Necessary because Perl cannot evaluate JavaScript
         * true/false when submitted in JSON.
         *
         * @example
         *
         * Always auto-focus the field:
         * <input auto-focus />
         *
         * Conditionally focus the field based on the state variable.
         * <input auto-focus="condition" />
         *
         * Call lost focus callback on focus lost.
         * <input auto-focus onFocusLost="handleFocusLost()" />
         */
        module.directive("boolToInt", [

            function() {
                return {
                    restrict: "A",
                    require: "ngModel",
                    priority: 99,
                    link: function(scope, elem, attrs, controller) {
                        controller.$formatters.push(function(modelValue) {
                            return !!modelValue;
                        });

                        controller.$parsers.push(function(viewValue) {
                            return viewValue ? 1 : 0;
                        });
                    }
                };
            }
        ]);
    }
);
