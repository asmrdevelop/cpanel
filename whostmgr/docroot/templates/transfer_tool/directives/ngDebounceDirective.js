/*
# templates/transfer_tool/directives/preventBubblingDirective.js    Copyright(c) 2020 cPanel, L.L.C.
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
        // https://gist.github.com/tommaitland/7579618
        /**
         * Angular directive that prevents input from being processed.  Useful when paired with an input filter or ajax request
         * to prevent rapid calling of underlining functionality.
         */
        app.directive("ngDebounce", ["$timeout",
            function($timeout) {
                return {
                    restrict: "A",
                    require: "ngModel",
                    priority: 99,
                    link: function(scope, elm, attr, ngModelCtrl) {
                        if (attr.type === "radio" || attr.type === "checkbox") {
                            return;
                        }

                        elm.unbind("input");

                        var debounce;

                        elm.bind("input", function() {
                            $timeout.cancel(debounce);
                            debounce = $timeout(function() {
                                scope.$apply(function() {
                                    ngModelCtrl.$setViewValue(elm.val());
                                });
                            }, 250);
                        });

                        elm.bind("blur", function() {

                            // http://stackoverflow.com/questions/12729122/prevent-error-digest-already-in-progress-when-calling-scope-apply
                            $timeout(function() {
                                scope.$apply(function() {
                                    ngModelCtrl.$setViewValue(elm.val());
                                });
                            });
                        });
                    }
                };
            }
        ]);
    }
);
