/*
# templates/contact_manager/directives/indeterminate.js   Copyright(c) 2020 cPanel, L.L.C.
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

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Angular directive that when attached to a checkbox will set indeterminate based on the passed in value.
         * This is sugar since we cannot set this attribute in HTML directly.
         */
        app.directive("cpIndeterminate", [

            function() {
                return {
                    restrict: "A",
                    scope: {
                        cpIndeterminate: "@",
                    },

                    link: function(scope, elem) {
                        scope.$watch("cpIndeterminate", function(newVal) {
                            var booleanVal = false;
                            if (newVal === "true") {
                                booleanVal = true;
                            }
                            elem.prop("indeterminate", booleanVal);
                        });

                    }
                };
            }
        ]);
    }
);
