/*
# templates/transfer_tool/directives/clickOnceDirective.js          Copyright(c) 2020 cPanel, L.L.C.
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
         * Angular directive which disables a button on form submit.
         * Original work found here: http://stackoverflow.com/a/19825570
         */
        app.directive("clickOnce", ["$timeout",
            function($timeout) {
                return {
                    restrict: "A",
                    link: function(scope, element, attrs) {
                        var replacementText = attrs.clickOnce;
                        element.bind("click", function() {
                            $timeout(function() {
                                if (replacementText) {
                                    element.html(replacementText);
                                }
                                element.attr("disabled", true);
                            }, 0);
                        });
                    }
                };
            }
        ]);
    }
);
