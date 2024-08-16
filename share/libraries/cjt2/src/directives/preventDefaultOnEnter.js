/*
# cjt/directives/preventDefaultOnEnter.js                           Copyright(c) 2020 cPanel, L.L.C.
#                                                                             All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
# TODO: This will not be needed if we go to 1.3.0 (ngModelOptions)
*/

/* global define: false */

/**
 * Angular directive that prevents default when tied to any input field.  Useful for blocking accident form submission
 */

function preventDefaultOnEnter() {
    return {
        restrict: "A",
        link: function(scope, elem, attrs) {
            elem.bind("keydown", function(event) {
                var code = event.keyCode || event.which;
                if (code === 13) {
                    if (!event.shiftKey) {
                        event.preventDefault();
                    }
                }
            });
        }
    };
}

define(
    [
        "angular"
    ],
    function(angular) {

        // Retrieve the application object
        angular.module("cjt2.directives.preventDefaultOnEnter", [])
            .directive("preventDefaultOnEnter", ["$timeout", preventDefaultOnEnter]);
    });
