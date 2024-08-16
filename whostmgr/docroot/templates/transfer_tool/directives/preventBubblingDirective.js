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
        /**
         * Angular directive which prevents event propogation.  Used in a Bootstrap dropdown menu with a form to prevent
         * accidental closure when interacting with the fields.
         */
        app.directive("preventBubbling", [

            function() {
                return {
                    restrict: "A",
                    link: function(scope, element) {
                        element.bind("click", function(event) {
                            event.preventDefault();
                            event.stopPropagation();
                        });
                    }
                };
            }
        ]);
    }
);
