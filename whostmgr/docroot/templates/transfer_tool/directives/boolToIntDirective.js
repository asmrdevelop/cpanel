/*
# templates/transfer_tool/directives/boolToIntDirective.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular directive that when attached to an element with an ng-model will render that model as true or false
         * but ensure that any changing will result in 1 or 0 values.  Necessary because Perl cannot evaluate JavaScript
         * true/false when submitted in JSON.
         */
        app.directive("boolToInt", [

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
